//! Scoring engine. M2 computes liveness and status buckets from probe
//! history on a schedule. Reviewer weighting and trust scores arrive in M5;
//! until then trust columns stay null and nothing fabricates a score.

use common::config::Config;
use sqlx::PgPool;
use std::time::Duration;

/// SPEC.md Section 12. liveness combines uptime over seven days with card
/// quality and a latency factor. Status buckets by uptime: live at 0.9 and
/// above, flaky between 0.5 and 0.9, down below 0.5, dormant with no valid
/// endpoint, measuring while under the minimum probe count (24 at the 30
/// minute cadence, 6 for daily probed web only agents).
const SCORE_SQL: &str = "
with observer_outage as (
  -- Hours where nearly every probe we sent failed are our outage, not
  -- theirs: excluded from uptime, shown as no data, never deleted.
  select date_trunc('hour', probed_at) as h
  from probe_results
  where probed_at > now() - interval '7 days'
  group by 1
  having count(*) > 100 and avg(ok::int) < 0.05
)
insert into agent_scores (
  agent_id, computed_at, liveness, uptime_7d, median_latency, trust,
  trust_confidence, raw_star_avg, feedback_total, feedback_kept,
  jobs_completed, jobs_disputed, rank_score, status, probes_7d, min_probes
)
select
  s.agent_id,
  now(),
  round(100 * (0.55 * coalesce(p.uptime, 0)
             + 0.30 * cq.card_quality
             + 0.15 * coalesce(p.latency_factor, 0))::numeric, 2),
  round(p.uptime::numeric, 4),
  p.median_latency,
  null,
  null,
  null,
  coalesce(f.total, 0),
  0,
  0,
  0,
  round((0.45 * 100 * (0.55 * coalesce(p.uptime, 0)
                     + 0.30 * cq.card_quality
                     + 0.15 * coalesce(p.latency_factor, 0)))::numeric, 2),
  case
    when p.probes is null or p.probes < s.min_probes then 'measuring'
    when p.uptime >= 0.9 then 'live'
    when p.uptime >= 0.5 then 'flaky'
    else 'down'
  end,
  coalesce(p.probes, 0),
  s.min_probes
from (
  select agent_id, min(case when cadence_secs <= 1800 then 24 else 6 end) as min_probes
  from probe_schedule group by agent_id
) s
join agents a using (agent_id)
cross join lateral (
  select (0.4 * (a.card_status = 'ok')::int
        + 0.3 * (jsonb_array_length(coalesce(a.endpoints, '[]'::jsonb)) > 0)::int
        + 0.2 * (a.name is not null and a.description is not null)::int
        + 0.1 * (a.declared_skills is not null)::int) as card_quality
) cq
left join lateral (
  select count(*) as probes,
         avg(ok::int)::float8 as uptime,
         percentile_cont(0.5) within group (order by latency_ms)::int as median_latency,
         greatest(0, least(1, 1 - (percentile_cont(0.5) within group (order by latency_ms) / 5000.0)))::float8 as latency_factor
  from probe_results pr
  where pr.agent_id = s.agent_id and pr.probed_at > now() - interval '7 days'
    and date_trunc('hour', pr.probed_at) not in (select h from observer_outage)
) p on true
left join lateral (
  select count(*) as total from feedback fb
  where fb.agent_id = s.agent_id and not fb.revoked
) f on true";

/// Refresh the registry snapshot the marketplace header reads. Run right
/// after scoring, when the numbers have just changed.
const STATS_SQL: &str = "
with latest as (
  select distinct on (agent_id) agent_id, status
  from agent_scores order by agent_id, computed_at desc
)
insert into registry_stats (
  id, registered, cards_fetched, cards_ok, with_endpoints, feedback,
  reviewers, live, flaky, down, measuring, probes_total, computed_at
)
select 1,
  (select count(*) from agents),
  (select count(*) from agents where card_fetched_at is not null),
  (select count(*) from agents where card_status = 'ok'),
  (select count(*) from agents
    where endpoints is not null and jsonb_array_length(endpoints) > 0),
  (select count(*) from feedback where not revoked),
  (select count(distinct reviewer) from feedback),
  count(*) filter (where status = 'live'),
  count(*) filter (where status = 'flaky'),
  count(*) filter (where status = 'down'),
  count(*) filter (where status = 'measuring'),
  (select count(*) from probe_results),
  now()
from latest
on conflict (id) do update set
  registered = excluded.registered,
  cards_fetched = excluded.cards_fetched,
  cards_ok = excluded.cards_ok,
  with_endpoints = excluded.with_endpoints,
  feedback = excluded.feedback,
  reviewers = excluded.reviewers,
  live = excluded.live,
  flaky = excluded.flaky,
  down = excluded.down,
  measuring = excluded.measuring,
  probes_total = excluded.probes_total,
  computed_at = excluded.computed_at";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    common::init_tracing("trust");
    let config = Config::from_env()?;
    let pool = common::connect_and_migrate(&config.database_url).await?;

    loop {
        match run_scoring(&pool).await {
            Ok(rows) => tracing::info!(rows, "scoring pass complete"),
            Err(e) => tracing::error!(%e, "scoring pass failed"),
        }
        match refresh_stats(&pool).await {
            Ok(()) => tracing::info!("registry snapshot refreshed"),
            Err(e) => tracing::error!(%e, "registry snapshot failed"),
        }
        tokio::time::sleep(Duration::from_secs(1800)).await;
    }
}

async fn run_scoring(pool: &PgPool) -> anyhow::Result<u64> {
    let result = sqlx::query(SCORE_SQL).execute(pool).await?;
    Ok(result.rows_affected())
}

async fn refresh_stats(pool: &PgPool) -> anyhow::Result<()> {
    sqlx::query(STATS_SQL).execute(pool).await?;
    Ok(())
}

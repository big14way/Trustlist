//! Scoring engine. M2 computes liveness and status buckets from probe
//! history on a schedule. Reviewer weighting and trust scores arrive in M5;
//! until then trust columns stay null and nothing fabricates a score.

mod score;
mod weights;

use common::config::Config;
use common::snapshot;
use sqlx::types::BigDecimal as Decimal;
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
  t.trust,
  t.confidence,
  t.raw_average,
  coalesce(t.feedback_total, f.total, 0),
  coalesce(t.feedback_kept, 0),
  0,
  0,
  round((0.45 * 100 * (0.55 * coalesce(p.uptime, 0)
                     + 0.30 * cq.card_quality
                     + 0.15 * coalesce(p.latency_factor, 0))
         + 0.35 * coalesce(t.trust, 0))::numeric, 2),
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
) f on true
left join agent_trust t on t.agent_id = s.agent_id";

/// Refresh the registry snapshot the marketplace header reads. Run right
/// after scoring, when the numbers have just changed.
const STATS_SQL: &str = "
with latest as (
  select distinct on (agent_id) agent_id, status
  from agent_scores order by agent_id, computed_at desc
)
insert into registry_stats (
  id, registered, cards_fetched, cards_ok, with_endpoints, feedback,
  reviewers, live, flaky, down, measuring, probes_total, computed_at,
  agents_rated, agents_scored, reviews_kept, reviewers_independent,
  largest_cluster_reviewers, largest_cluster_reviews
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
  now(),
  (select count(*) from agent_trust),
  (select count(*) from agent_trust where trust is not null),
  (select coalesce(sum(feedback_kept), 0) from agent_trust),
  (select count(*) from reviewer_weights where weight >= 1.0),
  (select coalesce(max(n), 0) from (
     select count(*) as n from reviewer_weights
     where cluster_id is not null group by cluster_id) c),
  (select coalesce(max(r), 0) from (
     select count(*) as r from feedback f
     join reviewer_weights w on w.reviewer = f.reviewer
     where w.cluster_id is not null group by w.cluster_id) c2)
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
  computed_at = excluded.computed_at,
  agents_rated = excluded.agents_rated,
  agents_scored = excluded.agents_scored,
  reviews_kept = excluded.reviews_kept,
  reviewers_independent = excluded.reviewers_independent,
  largest_cluster_reviewers = excluded.largest_cluster_reviewers,
  largest_cluster_reviews = excluded.largest_cluster_reviews";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    common::handle_version_flag("trust");
    common::init_tracing("trust");
    // `--once` runs a single pass and exits with the pass result. CI uses it
    // to build a real snapshot from the seed before publishing it, so the
    // snapshot pipeline is proved on every push instead of on one laptop.
    let once = std::env::args().any(|a| a == "--once");
    let config = Config::from_env()?;
    let pool = common::connect_and_migrate(&config.database_url).await?;

    loop {
        let result = one_pass(&pool).await;
        if once {
            return result;
        }
        if let Err(e) = result {
            tracing::error!(%e, "pass finished with failures, retrying next cycle");
        }
        tokio::time::sleep(Duration::from_secs(1800)).await;
    }
}

/// One full pass over the registry. Every stage runs even when an earlier one
/// fails, because a broken trust pass should not stop scoring forever, but
/// the failures are collected and returned so a single run can exit non zero.
async fn one_pass(pool: &PgPool) -> anyhow::Result<()> {
    let mut failures: Vec<String> = Vec::new();

    // Trust first: the scoring pass reads agent_trust, so computing it
    // afterwards would score every agent against the previous run.
    match run_trust(pool).await {
        Ok((reviewers, agents)) => {
            tracing::info!(reviewers, agents, "trust pass complete")
        }
        Err(e) => {
            tracing::error!(%e, "trust pass failed");
            failures.push(format!("trust pass: {e}"));
        }
    }
    match run_categories(pool).await {
        Ok(rows) => tracing::info!(rows, "categories assigned"),
        Err(e) => {
            tracing::error!(%e, "category pass failed");
            failures.push(format!("category pass: {e}"));
        }
    }
    match run_scoring(pool).await {
        Ok(rows) => tracing::info!(rows, "scoring pass complete"),
        Err(e) => {
            tracing::error!(%e, "scoring pass failed");
            failures.push(format!("scoring pass: {e}"));
        }
    }
    match refresh_stats(pool).await {
        Ok(()) => tracing::info!("registry snapshot refreshed"),
        Err(e) => {
            tracing::error!(%e, "registry snapshot failed");
            failures.push(format!("registry snapshot: {e}"));
        }
    }
    match build_snapshot(pool).await {
        Ok(Some((id, root, count))) => {
            tracing::info!(id, %root, agents = count, "merkle snapshot built")
        }
        Ok(None) => tracing::info!("no measured agents yet, no snapshot built"),
        Err(e) => {
            tracing::error!(%e, "snapshot build failed");
            failures.push(format!("snapshot build: {e}"));
        }
    }

    if failures.is_empty() {
        Ok(())
    } else {
        anyhow::bail!("{}", failures.join("; "))
    }
}

async fn run_scoring(pool: &PgPool) -> anyhow::Result<u64> {
    let result = sqlx::query(SCORE_SQL).execute(pool).await?;
    Ok(result.rows_affected())
}

/// Classify agents into the categories the marketplace filters on.
async fn run_categories(pool: &PgPool) -> anyhow::Result<u64> {
    let result = sqlx::query(CATEGORY_SQL).execute(pool).await?;
    Ok(result.rows_affected())
}

/// Build a Merkle snapshot of the current scores and store it with its full
/// leaf set. Publishing the root on chain is a separate, deliberate step
/// (contracts/script/PublishSnapshot.s.sol) so the key that signs never sits
/// in a long running service.
async fn build_snapshot(pool: &PgPool) -> anyhow::Result<Option<(i64, String, usize)>> {
    use snapshot::U256;

    // Only agents we have actually measured belong in a snapshot. Publishing
    // a root over agents we have never probed would be publishing noise.
    type ScoreRow = (String, Option<Decimal>, Option<Decimal>, Option<Decimal>);
    let rows: Vec<ScoreRow> = sqlx::query_as(
        "select distinct on (s.agent_id)
                    s.agent_id::text, s.liveness, s.trust, s.trust_confidence
             from agent_scores s
             where s.status in ('live','flaky','down')
             order by s.agent_id, s.computed_at desc",
    )
    .fetch_all(pool)
    .await?;

    if rows.is_empty() {
        return Ok(None);
    }

    let computed_at = chrono::Utc::now().timestamp() as u64;
    let mut leaves = Vec::with_capacity(rows.len());
    let mut records = Vec::with_capacity(rows.len());

    for (agent_id, liveness, trust, confidence) in rows {
        let to_f = |v: Option<Decimal>| -> Option<f64> {
            v.and_then(|d| d.to_string().parse::<f64>().ok())
        };
        let l = snapshot::to_bps(to_f(liveness));
        let t = snapshot::to_bps(to_f(trust));
        let c = snapshot::to_bps(to_f(confidence).map(|v| v * 100.0));
        let id: U256 = agent_id.parse()?;
        let leaf = snapshot::leaf_hash(id, l, t, c, computed_at);
        leaves.push(leaf);
        records.push((agent_id, l, t, c, leaf));
    }

    let payload = snapshot::Payload {
        merkle_root: String::new(), // filled in below, once the root is known
        agent_count: records.len() as u32,
        computed_at,
        encoding: snapshot::ENCODING,
        leaves: records
            .iter()
            .map(|(agent_id, l, t, c, leaf)| snapshot::Leaf {
                agent_id: agent_id.clone(),
                liveness: *l,
                trust: *t,
                confidence: *c,
                computed_at,
                leaf: format!("{leaf}"),
            })
            .collect(),
    };

    let root = match snapshot::merkle_root(&leaves) {
        Some(r) => r,
        None => return Ok(None),
    };

    // Refuse to store a tree we cannot prove against ourselves.
    let probe = snapshot::merkle_proof(&leaves, 0);
    if !snapshot::verify_proof(root, leaves[0], &probe) {
        anyhow::bail!("built a snapshot whose own proof does not verify");
    }

    let root_hex = format!("{root}");
    let payload = snapshot::Payload {
        merkle_root: root_hex.clone(),
        ..payload
    };

    let id: (i64,) = sqlx::query_as(
        "insert into snapshots (merkle_root, agent_count, computed_at, root_hex, published, payload)
         values ($1, $2, to_timestamp($3), $4, false, $5) returning id",
    )
    .bind(root.as_slice())
    .bind(records.len() as i32)
    .bind(computed_at as i64)
    .bind(&root_hex)
    .bind(sqlx::types::Json(&payload))
    .fetch_one(pool)
    .await?;

    let mut tx = pool.begin().await?;
    for (position, (agent_id, l, t, c, leaf)) in records.iter().enumerate() {
        sqlx::query(
            "insert into snapshot_leaves (snapshot_id, agent_id, position, liveness, trust, confidence, leaf)
             values ($1, $2::numeric, $3, $4, $5, $6, $7)
             on conflict (snapshot_id, agent_id) do nothing",
        )
        .bind(id.0)
        .bind(agent_id)
        .bind(position as i32)
        .bind(*l as i32)
        .bind(*t as i32)
        .bind(*c as i32)
        .bind(leaf.as_slice())
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;

    // A published snapshot is permanent evidence and is kept forever. An
    // unpublished one is only the current candidate, and at one build every
    // cycle over the whole registry the leaf sets would otherwise grow
    // without bound, so older candidates are dropped.
    let pruned = sqlx::query("delete from snapshots where published = false and id <> $1")
        .bind(id.0)
        .execute(pool)
        .await?
        .rows_affected();
    if pruned > 0 {
        tracing::info!(pruned, "dropped superseded snapshot candidates");
    }

    Ok(Some((id.0, root_hex, records.len())))
}

async fn refresh_stats(pool: &PgPool) -> anyhow::Result<()> {
    sqlx::query(STATS_SQL).execute(pool).await?;
    Ok(())
}

/// Assign categories from the text an agent's own owner wrote in its card.
/// Every rule needs an action word and the thing being acted on, so the
/// boilerplate that fills this registry ("track trust, alignment") does not
/// masquerade as a monitoring agent. The rules are published verbatim at
/// /v1/methodology, and anything unmatched is filed as other rather than
/// guessed at.
const CATEGORY_SQL: &str = "
update agents a
set categories = case when cardinality(c.cats) = 0 then array['other'] else c.cats end
from (
  select agent_id,
         array_remove(array[
           case when d ~ '(monitor|watch|track|alert)'
                 and d ~ '(wallet|position|market|price|portfolio|balance|liquidat|treasury)'
                then 'monitoring' end,
           case when d ~ 'grid' and d ~ '(trad|order|bot|strateg|range)'
                then 'grid-trading' end,
           case when d ~ '(health factor|liquidation|collateral)'
                then 'health-factor' end,
           case when d ~ '(yield|apy|apr|farming|staking)'
                then 'yield' end,
           case when d ~ '(rebalanc|liquidity range|lp position|concentrated liquidity)'
                then 'rebalancing' end,
           case when d ~ '(pancakeswap|pancake)'
                then 'pancakeswap' end
         ], null) as cats
  from (
    select agent_id,
           lower(coalesce(name,'') || ' ' || coalesce(description,'')) as d
    from agents where card_status = 'ok'
  ) t
) c
where c.agent_id = a.agent_id
  and a.categories is distinct from
      (case when cardinality(c.cats) = 0 then array['other'] else c.cats end)";

/// One row of per reviewer behaviour joined to its funding trace:
/// reviewer, feedback count, revoked count, distinct agents, min and max
/// score given, seconds between funding and first review, outbound transfer
/// count, and funder.
type ReviewerRow = (
    Vec<u8>,
    i64,
    i64,
    i64,
    f64,
    f64,
    Option<i64>,
    Option<i32>,
    Option<Vec<u8>>,
);

/// Recompute reviewer independence and agent trust from what the registry
/// and the funding traces actually contain.
async fn run_trust(pool: &PgPool) -> anyhow::Result<(usize, usize)> {
    // Per reviewer behaviour, joined to the funding trace.
    let rows: Vec<ReviewerRow> = sqlx::query_as(
        "select f.reviewer,
                    count(*)::bigint,
                    count(*) filter (where f.revoked)::bigint,
                    count(distinct f.agent_id)::bigint,
                    min(f.value / power(10, f.value_decimals))::float8,
                    max(f.value / power(10, f.value_decimals))::float8,
                    -- Seconds between the wallet being funded and its
                    -- first review. A wallet funded minutes before it
                    -- starts voting is the oldest trick there is.
                    extract(epoch from (min(f.block_time) - rf.first_funded_at))::bigint,
                    rf.outbound_count,
                    rf.funder
             from feedback f
             left join reviewer_funding rf on rf.reviewer = f.reviewer
             group by f.reviewer, rf.outbound_count, rf.funder, rf.first_funded_at",
    )
    .fetch_all(pool)
    .await?;

    let facts: Vec<weights::ReviewerFacts> = rows
        .into_iter()
        .map(
            |(reviewer, count, revoked, _agents, min_s, max_s, secs, outbound, funder)| {
                weights::ReviewerFacts {
                    reviewer,
                    feedback_count: count,
                    revoked_count: revoked,
                    min_score: min_s,
                    max_score: max_s,
                    seconds_funded_before_first_review: secs,
                    outbound_count: outbound.unwrap_or(0),
                    funder,
                }
            },
        )
        .collect();

    // Reviewers who keep turning up on the same agents as each other. This
    // is what catches a farm that drips its reviews out over weeks instead
    // of firing them off in a burst.
    let coreview: Vec<(Vec<u8>, i64)> = sqlx::query_as(
        "with pairs as (
           select a.reviewer as r1, b.reviewer as r2, count(*) as shared
           from (select distinct reviewer, agent_id from feedback) a
           join (select distinct reviewer, agent_id from feedback) b
             on a.agent_id = b.agent_id and a.reviewer <> b.reviewer
           group by 1, 2
         )
         select r1, count(*)::bigint from pairs where shared >= $1 group by r1",
    )
    .bind(weights::MIN_SHARED_AGENTS)
    .fetch_all(pool)
    .await?;
    let coreview_peers: std::collections::HashMap<Vec<u8>, i64> = coreview.into_iter().collect();

    // A rates an agent owned by B while B rates an agent owned by A.
    let recip_rows: Vec<(Vec<u8>,)> = sqlx::query_as(
        "with rates_owner as (
           select distinct f.reviewer, a.owner
           from feedback f join agents a on a.agent_id = f.agent_id
         )
         select distinct x.reviewer
         from rates_owner x
         join rates_owner y on y.reviewer = x.owner and y.owner = x.reviewer",
    )
    .fetch_all(pool)
    .await?;
    let reciprocal: std::collections::HashSet<Vec<u8>> =
        recip_rows.into_iter().map(|(r,)| r).collect();

    let clusters = weights::cluster_by_funding(&facts);
    let sizes = weights::cluster_sizes(&clusters);
    let computed = weights::compute(&facts, &clusters, &sizes, &coreview_peers, &reciprocal);

    let mut tx = pool.begin().await?;
    for w in &computed {
        sqlx::query(
            "insert into reviewer_weights (reviewer, weight, cluster_id, flags, computed_at)
             values ($1, $2, $3, $4, now())
             on conflict (reviewer) do update set
               weight = excluded.weight,
               cluster_id = excluded.cluster_id,
               flags = excluded.flags,
               computed_at = now()",
        )
        .bind(&w.reviewer)
        .bind(w.weight)
        .bind(w.cluster_id)
        .bind(&w.flags)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;

    // Score every agent from the feedback that survived weighting.
    let fb_rows: Vec<(String, Vec<u8>, f64, i32)> = sqlx::query_as(
        "select agent_id::text, reviewer, value::float8, value_decimals
         from feedback where not revoked",
    )
    .fetch_all(pool)
    .await?;
    let feedback: Vec<score::Feedback> = fb_rows
        .into_iter()
        .map(|(agent_id, reviewer, value, decimals)| score::Feedback {
            agent_id,
            reviewer,
            value,
            decimals,
        })
        .collect();

    let weight_map: std::collections::HashMap<Vec<u8>, f64> = computed
        .iter()
        .map(|w| (w.reviewer.clone(), w.weight))
        .collect();
    let scored = score::compute(&feedback, &weight_map, &clusters);

    let mut tx = pool.begin().await?;
    for a in &scored {
        sqlx::query(
            "insert into agent_trust (agent_id, trust, confidence, raw_average,
                                      feedback_total, feedback_kept, computed_at)
             values ($1::numeric, $2, $3, $4, $5, $6, now())
             on conflict (agent_id) do update set
               trust = excluded.trust,
               confidence = excluded.confidence,
               raw_average = excluded.raw_average,
               feedback_total = excluded.feedback_total,
               feedback_kept = excluded.feedback_kept,
               computed_at = now()",
        )
        .bind(&a.agent_id)
        .bind(a.trust)
        .bind(a.confidence)
        .bind(a.raw_average)
        .bind(a.feedback_total)
        .bind(a.feedback_kept)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;

    Ok((computed.len(), scored.len()))
}

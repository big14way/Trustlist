//! The endpoint probe loop: keep the schedule in sync with declared
//! endpoints, probe what is due, record every attempt in probe_results.
//! SPEC.md Section 12: a 401, 402, or 403 is alive (a paywalled agent is a
//! working agent); dns, tls, refused, timeout, 404, and 5xx are down.

use crate::fetch::{self, FailureKind};
use sha2::Digest;
use sqlx::PgPool;

/// Sync probe_schedule from agents.endpoints: new endpoints join the
/// schedule immediately, endpoints that vanished from cards are removed.
/// Web endpoints on hosts serving over 100 registrations probe daily,
/// everything else every 30 minutes.
pub async fn sync_schedule(pool: &PgPool, default_secs: i32) -> anyhow::Result<u64> {
    let inserted = sqlx::query(
        "insert into probe_schedule (agent_id, endpoint_url, kind, host, cadence_secs, next_due)
         select a.agent_id,
                e->>'url',
                coalesce(e->>'kind', 'unknown'),
                lower(substring(e->>'url' from 'https?://([^/]+)')),
                case when coalesce(e->>'kind','unknown') = 'web'
                          and lower(substring(e->>'url' from 'https?://([^/]+)')) in (
                            select lower(substring(x->>'url' from 'https?://([^/]+)'))
                            from agents, jsonb_array_elements(endpoints) x
                            group by 1 having count(*) > 100
                          )
                     then 86400 else $1 end,
                now()
         from agents a, jsonb_array_elements(a.endpoints) e
         where e->>'url' like 'http%'
         on conflict (agent_id, endpoint_url) do nothing",
    )
    .bind(default_secs)
    .execute(pool)
    .await?
    .rows_affected();

    sqlx::query(
        "delete from probe_schedule s
         where not exists (
           select 1 from agents a, jsonb_array_elements(a.endpoints) e
           where a.agent_id = s.agent_id and e->>'url' = s.endpoint_url
         )",
    )
    .execute(pool)
    .await?;
    Ok(inserted)
}

pub struct ProbeOutcome {
    pub ok: bool,
    pub http_status: Option<i32>,
    pub latency_ms: Option<i32>,
    pub failure_kind: Option<&'static str>,
    pub body_hash: Option<Vec<u8>>,
}

pub async fn probe_endpoint(client: &reqwest::Client, url: &str) -> ProbeOutcome {
    let started = std::time::Instant::now();
    match fetch::guarded_get(client, url).await {
        Ok(res) => {
            let latency = started.elapsed().as_millis() as i32;
            let alive = res.status < 500 && res.status != 404;
            let hash = sha2::Sha256::digest(&res.body[..res.body.len().min(4096)]);
            ProbeOutcome {
                ok: alive,
                http_status: Some(res.status as i32),
                latency_ms: Some(latency),
                failure_kind: if alive { None } else { Some("http_error") },
                body_hash: Some(hash.to_vec()),
            }
        }
        Err(kind) => ProbeOutcome {
            ok: false,
            http_status: None,
            latency_ms: None,
            failure_kind: Some(match kind {
                FailureKind::Dns => "dns",
                FailureKind::Tls => "tls",
                FailureKind::Timeout => "timeout",
                FailureKind::ConnRefused => "conn_refused",
                FailureKind::BadBody => "bad_body",
                FailureKind::PrivateBlocked | FailureKind::BadUrl => "bad_url",
                FailureKind::TooManyRedirects | FailureKind::HttpError => "http_error",
            }),
            body_hash: None,
        },
    }
}

pub async fn record(
    pool: &PgPool,
    agent_id: &str,
    url: &str,
    outcome: &ProbeOutcome,
) -> anyhow::Result<()> {
    sqlx::query(
        "insert into probe_results (agent_id, endpoint_url, ok, http_status, latency_ms, failure_kind, body_hash)
         values ($1::numeric, $2, $3, $4, $5, $6, $7)",
    )
    .bind(agent_id)
    .bind(url)
    .bind(outcome.ok)
    .bind(outcome.http_status)
    .bind(outcome.latency_ms)
    .bind(outcome.failure_kind)
    .bind(&outcome.body_hash)
    .execute(pool)
    .await?;
    sqlx::query(
        "update probe_schedule
         set next_due = now() + make_interval(secs => cadence_secs)
         where agent_id = $1::numeric and endpoint_url = $2",
    )
    .bind(agent_id)
    .bind(url)
    .execute(pool)
    .await?;
    Ok(())
}

/// Claim a batch of due endpoints in random order: a batch dominated by one
/// bulk host would park every worker behind that host's shared rate limit.
pub async fn due_batch(pool: &PgPool, limit: i64) -> anyhow::Result<Vec<(String, String)>> {
    let rows: Vec<(String, String)> = sqlx::query_as(
        "select agent_id::text, endpoint_url from probe_schedule
         where next_due <= now()
         order by random()
         limit $1",
    )
    .bind(limit)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

//! Card fetcher (M1) and endpoint prober (M2). The M1 half resolves every
//! agent's tokenURI into name, description, and classified endpoints, with
//! per host rate limiting and the SSRF guard on every network touch.

mod card;
mod fetch;
mod probe;

use anyhow::Context;
use common::config::Config;
use fetch::FailureKind;
use governor::{Quota, RateLimiter};
use sqlx::PgPool;
use std::num::NonZeroU32;
use std::sync::Arc;
use std::time::Duration;

type HostLimiter = RateLimiter<
    String,
    governor::state::keyed::DashMapStateStore<String>,
    governor::clock::DefaultClock,
>;

struct Fetcher {
    pool: PgPool,
    client: reqwest::Client,
    ipfs_gateway: String,
    ipfs_gateway_fallback: Option<String>,
    /// Ordinary hosts: one request per ten seconds, the good citizen rule.
    host_limiter: Arc<HostLimiter>,
    /// Bulk hosts serving over one hundred registrations (metadata farms,
    /// S3 buckets, IPFS gateways): a pooled five per second. At one per ten
    /// seconds a single 100k agent host would take twelve days, which is
    /// slower than the registry grows. Documented on the methodology page.
    bulk_limiter: Arc<HostLimiter>,
    bulk_hosts: std::sync::RwLock<std::collections::HashSet<String>>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    common::init_tracing("prober");
    let config = Config::from_env()?;
    let pool = common::connect_and_migrate(&config.database_url).await?;

    let strict = Quota::with_period(Duration::from_secs(10))
        .context("quota")?
        .allow_burst(NonZeroU32::new(2).context("burst")?);
    let bulk = Quota::with_period(Duration::from_millis(200))
        .context("bulk quota")?
        .allow_burst(NonZeroU32::new(10).context("bulk burst")?);
    let fetcher = Arc::new(Fetcher {
        pool: pool.clone(),
        client: fetch::build_client()?,
        ipfs_gateway: config.ipfs_gateway.clone(),
        ipfs_gateway_fallback: config.ipfs_gateway_fallback.clone(),
        host_limiter: Arc::new(RateLimiter::keyed(strict)),
        bulk_limiter: Arc::new(RateLimiter::keyed(bulk)),
        bulk_hosts: std::sync::RwLock::new(std::collections::HashSet::new()),
    });

    let workers = config.probe_concurrency.clamp(1, 256);
    let interval = config.probe_interval_secs;

    // Endpoint probe loop runs beside the card fetcher.
    {
        let f = fetcher.clone();
        let pool = pool.clone();
        tokio::spawn(async move {
            loop {
                if let Err(e) = probe_pass(&f, &pool, interval as i32, workers).await {
                    tracing::warn!(%e, "probe pass failed");
                }
                tokio::time::sleep(Duration::from_secs(15)).await;
            }
        });
    }

    tracing::info!(workers, "card fetcher starting");
    loop {
        // Refresh which hosts count as bulk before each batch.
        let bulk_rows: Vec<(String,)> = sqlx::query_as(
            "select lower(substring(token_uri from 'https?://([^/]+)'))
             from agents where token_uri like 'http%'
             group by 1 having count(*) > 100",
        )
        .fetch_all(&pool)
        .await?;
        if let Ok(mut set) = fetcher.bulk_hosts.write() {
            set.clear();
            set.extend(bulk_rows.into_iter().map(|(h,)| h));
        }
        // Random order interleaves hosts so one slow host cannot stall a
        // whole batch behind its rate limit.
        let batch: Vec<(String, String)> = sqlx::query_as(
            "select agent_id::text, token_uri from agents
             where card_fetched_at is null and token_uri is not null and token_uri <> ''
             order by random()
             limit 2000",
        )
        .fetch_all(&pool)
        .await?;
        if batch.is_empty() {
            tokio::time::sleep(Duration::from_secs(30)).await;
            continue;
        }
        let mut handles = Vec::new();
        for chunk in batch.chunks(batch.len().div_ceil(workers)) {
            let chunk = chunk.to_vec();
            let f = fetcher.clone();
            handles.push(tokio::spawn(async move {
                for (agent_id, uri) in chunk {
                    if let Err(e) = f.fetch_one(&agent_id, &uri).await {
                        tracing::warn!(agent_id, %e, "card fetch failed");
                    }
                }
            }));
        }
        for h in handles {
            if let Err(e) = h.await {
                tracing::error!(%e, "worker panicked");
            }
        }
    }
}

impl Fetcher {
    async fn fetch_one(&self, agent_id: &str, uri: &str) -> anyhow::Result<()> {
        let (status, bytes) = self.resolve(uri).await;
        match bytes {
            Some(body) => match card::parse_card(&body) {
                Ok(parsed) => {
                    let endpoints_json = serde_json::Value::Array(
                        parsed
                            .endpoints
                            .iter()
                            .map(|(kind, url)| serde_json::json!({ "kind": kind, "url": url }))
                            .collect(),
                    );
                    let card_raw: serde_json::Value =
                        serde_json::from_slice(&body).unwrap_or(serde_json::Value::Null);
                    sqlx::query(
                        "update agents set
                           card_fetched_at = now(), card_status = 'ok', card_raw = $2,
                           name = $3, description = $4, endpoints = $5,
                           declared_skills = $6, trust_models = $7
                         where agent_id = $1::numeric",
                    )
                    .bind(agent_id)
                    .bind(&card_raw)
                    .bind(parsed.name.as_deref().map(|s| truncate(s, 200)))
                    .bind(parsed.description.as_deref().map(|s| truncate(s, 2000)))
                    .bind(&endpoints_json)
                    .bind(&parsed.skills)
                    .bind(&parsed.trust_models)
                    .execute(&self.pool)
                    .await?;
                }
                Err(kind) => {
                    self.mark(agent_id, kind).await?;
                }
            },
            None => {
                self.mark(agent_id, &status).await?;
            }
        }
        Ok(())
    }

    async fn mark(&self, agent_id: &str, status: &str) -> anyhow::Result<()> {
        sqlx::query(
            "update agents set card_fetched_at = now(), card_status = $2 where agent_id = $1::numeric",
        )
        .bind(agent_id)
        .bind(status)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Apply the tiered per host rate limit for any outbound URL.
    async fn wait_for_host(&self, candidate: &str) {
        if let Ok(parsed) = candidate.parse::<url::Url>() {
            if let Some(host) = parsed.host_str() {
                let host = host.to_ascii_lowercase();
                let is_bulk = self
                    .bulk_hosts
                    .read()
                    .map(|set| set.contains(&host))
                    .unwrap_or(false);
                if is_bulk {
                    self.bulk_limiter.until_key_ready(&host).await;
                } else {
                    self.host_limiter.until_key_ready(&host).await;
                }
            }
        }
    }

    /// Resolve a tokenURI to card bytes. Returns (status_label, bytes).
    async fn resolve(&self, uri: &str) -> (String, Option<Vec<u8>>) {
        if uri.starts_with("data:") {
            return match card::decode_data_uri(uri) {
                Some(bytes) => ("ok".into(), Some(bytes)),
                None => ("invalid_json".into(), None),
            };
        }
        let candidates: Vec<String> = if let Some(path) = uri.strip_prefix("ipfs://") {
            let mut v = vec![format!("{}/ipfs/{}", self.ipfs_gateway, path)];
            if let Some(fb) = &self.ipfs_gateway_fallback {
                v.push(format!("{fb}/ipfs/{path}"));
            }
            v
        } else if uri.starts_with("http://") || uri.starts_with("https://") {
            vec![uri.to_owned()]
        } else {
            return ("invalid_uri".into(), None);
        };

        let mut last = "unreachable".to_owned();
        for candidate in candidates {
            self.wait_for_host(&candidate).await;
            match fetch::guarded_get(&self.client, &candidate).await {
                Ok(res) if (200..300).contains(&res.status) => {
                    return ("ok".into(), Some(res.body));
                }
                Ok(res) => {
                    last = format!("http_{}", res.status);
                }
                Err(FailureKind::PrivateBlocked) => {
                    return ("private_blocked".into(), None);
                }
                Err(kind) => {
                    last = kind.as_str().to_owned();
                }
            }
        }
        (last, None)
    }
}

fn truncate(s: &str, max: usize) -> String {
    s.chars().take(max).collect()
}

/// One probe pass: refresh the schedule, take everything due, probe it
/// through the tiered rate limiters, and append the results.
async fn probe_pass(
    f: &Arc<Fetcher>,
    pool: &PgPool,
    default_cadence: i32,
    workers: usize,
) -> anyhow::Result<()> {
    let added = probe::sync_schedule(pool, default_cadence).await?;
    if added > 0 {
        tracing::info!(added, "endpoints joined the probe schedule");
    }
    let due = probe::due_batch(pool, 4000).await?;
    if due.is_empty() {
        return Ok(());
    }
    let total = due.len();
    let mut handles = Vec::new();
    for chunk in due.chunks(total.div_ceil(workers)) {
        let chunk = chunk.to_vec();
        let f = f.clone();
        let pool = pool.clone();
        handles.push(tokio::spawn(async move {
            for (agent_id, url) in chunk {
                f.wait_for_host(&url).await;
                let outcome = probe::probe_endpoint(&f.client, &url).await;
                if let Err(e) = probe::record(&pool, &agent_id, &url, &outcome).await {
                    tracing::warn!(agent_id, %e, "recording probe failed");
                }
            }
        }));
    }
    for h in handles {
        if let Err(e) = h.await {
            tracing::error!(%e, "probe worker panicked");
        }
    }
    tracing::info!(total, "probe batch complete");
    Ok(())
}

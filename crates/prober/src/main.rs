//! Card fetcher (M1) and endpoint prober (M2). The M1 half resolves every
//! agent's tokenURI into name, description, and classified endpoints, with
//! per host rate limiting and the SSRF guard on every network touch.

mod card;
mod fetch;

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
    host_limiter: Arc<HostLimiter>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    common::init_tracing("prober");
    let config = Config::from_env()?;
    let pool = common::connect_and_migrate(&config.database_url).await?;

    // One request per 10 seconds per host, the good citizen rule.
    let quota = Quota::with_period(Duration::from_secs(10))
        .context("quota")?
        .allow_burst(NonZeroU32::new(2).context("burst")?);
    let fetcher = Arc::new(Fetcher {
        pool: pool.clone(),
        client: fetch::build_client()?,
        ipfs_gateway: config.ipfs_gateway.clone(),
        ipfs_gateway_fallback: config.ipfs_gateway_fallback.clone(),
        host_limiter: Arc::new(RateLimiter::keyed(quota)),
    });

    let workers = config.probe_concurrency.clamp(1, 256);
    tracing::info!(workers, "card fetcher starting");
    loop {
        let batch: Vec<(String, String)> = sqlx::query_as(
            "select agent_id::text, token_uri from agents
             where card_fetched_at is null and token_uri is not null and token_uri <> ''
             order by agent_id
             limit 1000",
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
            if let Ok(parsed) = candidate.parse::<url::Url>() {
                if let Some(host) = parsed.host_str() {
                    self.host_limiter.until_key_ready(&host.to_owned()).await;
                }
            }
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

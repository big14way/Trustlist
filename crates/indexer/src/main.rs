//! Registry log ingestion: backfill from deploy block to head, then follow
//! head at a confirmation depth with reorg detection. SPEC.md Section 11.

mod events;
mod ingest;

use alloy::primitives::Address;
use alloy::providers::{Provider, ProviderBuilder};
use anyhow::Context;
use common::config::Config;
use ingest::{Ingestor, Registry, CONFIRM_DEPTH};
use std::time::Duration;

/// Implementation deploy blocks, verified via Sourcify on 17 Aug 2026.
/// Registrations through the proxy cannot precede these.
const IDENTITY_DEPLOY_BLOCK: u64 = 78_255_281;
const REPUTATION_DEPLOY_BLOCK: u64 = 79_027_282;

const USER_AGENT: &str = "TrustList/0.1 (+https://github.com/big14way/Trustlist)";

fn make_provider(url: &str) -> anyhow::Result<impl Provider + Clone> {
    let client = reqwest::Client::builder()
        .user_agent(USER_AGENT)
        .timeout(Duration::from_secs(30))
        .build()?;
    let parsed: url::Url = url.parse().context("rpc url")?;
    let transport = alloy::transports::http::Http::with_client(client, parsed);
    let rpc = alloy::rpc::client::RpcClient::new(transport, false);
    Ok(ProviderBuilder::new().connect_client(rpc))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    common::init_tracing("indexer");
    let config = Config::from_env()?;
    let pool = common::connect_and_migrate(&config.database_url).await?;

    let identity: Address = config
        .identity_registry
        .parse()
        .context("IDENTITY_REGISTRY")?;
    let reputation: Address = config
        .reputation_registry
        .parse()
        .context("REPUTATION_REGISTRY")?;

    // Primary and fallback providers. On repeated primary failure the loop
    // below swaps to the fallback and logs the switch.
    let primary = make_provider(&config.bsc_rpc_http)?;
    let fallback = config
        .bsc_rpc_http_fallback
        .as_deref()
        .map(make_provider)
        .transpose()?;

    let mut ingestor = Ingestor::new(primary.clone(), pool.clone());
    let mut consecutive_failures: u32 = 0;
    let mut on_fallback = false;

    let targets = [
        (Registry::Identity, identity, IDENTITY_DEPLOY_BLOCK),
        (Registry::Reputation, reputation, REPUTATION_DEPLOY_BLOCK),
    ];
    let mut next: Vec<u64> = Vec::with_capacity(targets.len());
    for (_, addr, deploy) in &targets {
        next.push(ingestor.start_block(*addr, *deploy).await?);
    }

    loop {
        let head = match ingestor.provider.get_block_number().await {
            Ok(h) => {
                consecutive_failures = 0;
                h.saturating_sub(CONFIRM_DEPTH)
            }
            Err(e) => {
                consecutive_failures += 1;
                tracing::warn!(%e, consecutive_failures, "head fetch failed");
                if consecutive_failures >= 5 {
                    if let Some(fb) = &fallback {
                        on_fallback = !on_fallback;
                        tracing::warn!(on_fallback, "switching rpc provider");
                        ingestor.provider = if on_fallback {
                            fb.clone()
                        } else {
                            primary.clone()
                        };
                        consecutive_failures = 0;
                    }
                }
                tokio::time::sleep(Duration::from_secs(5)).await;
                continue;
            }
        };

        let mut all_caught_up = true;
        for (i, (registry, addr, _)) in targets.iter().enumerate() {
            if next[i] > head {
                continue;
            }
            all_caught_up = false;
            // Reorg check only matters near head, where our stored boundary
            // hash could have been replaced.
            if head.saturating_sub(next[i]) < 1_000 {
                if let Some(rewind) = ingestor.check_reorg(*addr).await? {
                    tracing::warn!(
                        registry = registry.name(),
                        rewind,
                        "reorg detected, rewinding"
                    );
                    next[i] = rewind;
                }
            }
            next[i] = ingestor
                .ingest_chunk(*registry, *addr, next[i], head)
                .await?;
        }

        if all_caught_up {
            tokio::time::sleep(Duration::from_secs(10)).await;
        }
    }
}

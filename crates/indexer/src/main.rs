//! Registry log ingestion: backfill from deploy block to head, then follow
//! head at a confirmation depth with reorg detection. SPEC.md Section 11.

mod events;
mod ingest;
mod jobs;

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
    // http1 only and no idle reuse: bloXroute tarpits reused connections
    // under sustained load, which stalled requests past any timeout.
    let client = reqwest::Client::builder()
        .user_agent(USER_AGENT)
        .timeout(Duration::from_secs(30))
        .connect_timeout(Duration::from_secs(10))
        .http1_only()
        .pool_max_idle_per_host(0)
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

    // The hire rail follower runs beside the registry followers. It is
    // optional: with no HIRE_RAIL configured there is nothing to follow yet.
    if let Some(rail_addr) = config.hire_rail.clone() {
        let rail: Address = rail_addr.parse().context("HIRE_RAIL")?;
        let kernel: Address = config
            .hire_rail_kernel
            .clone()
            .unwrap_or_else(|| config.agentic_commerce.clone())
            .parse()
            .context("HIRE_RAIL_KERNEL")?;
        let rail_rpc = config
            .hire_rail_rpc
            .clone()
            .unwrap_or_else(|| config.bsc_rpc_http.clone());
        let rail_provider = make_provider(&rail_rpc)?;
        let mut follower = jobs::JobFollower {
            provider: rail_provider,
            pool: pool.clone(),
            rail,
            kernel,
            chain_id: config.hire_rail_chain_id,
        };
        let deploy_block = config.hire_rail_deploy_block;
        tokio::spawn(async move {
            let mut next = match follower.start_block(deploy_block).await {
                Ok(b) => b,
                Err(e) => {
                    tracing::error!(%e, "rail follower could not resume");
                    return;
                }
            };
            tracing::info!(%rail, chain_id = follower.chain_id, from = next, "hire rail follower starting");
            loop {
                match follower.provider.get_block_number().await {
                    Ok(head) => {
                        if next <= head {
                            let to = (next + 1_999).min(head);
                            match follower.ingest(next, to).await {
                                Ok(n) => next = n,
                                Err(e) => tracing::warn!(%e, "rail ingest failed"),
                            }
                        }
                    }
                    Err(e) => tracing::warn!(%e, "rail head fetch failed"),
                }
                if let Err(e) = follower.reconcile().await {
                    tracing::warn!(%e, "job reconcile failed");
                }
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        });
    }

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
            Ok(h) => h.saturating_sub(CONFIRM_DEPTH),
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
        let mut had_error = false;
        for (i, (registry, addr, _)) in targets.iter().enumerate() {
            if next[i] > head {
                continue;
            }
            all_caught_up = false;
            // Reorg check only matters near head, where our stored boundary
            // hash could have been replaced. Transient failures must never
            // kill the process; log, back off, and resume from saved state.
            if head.saturating_sub(next[i]) < 1_000 {
                match ingestor.check_reorg(*addr).await {
                    Ok(Some(rewind)) => {
                        tracing::warn!(
                            registry = registry.name(),
                            rewind,
                            "reorg detected, rewinding"
                        );
                        next[i] = rewind;
                    }
                    Ok(None) => {}
                    Err(e) => {
                        tracing::warn!(registry = registry.name(), %e, "reorg check failed");
                        had_error = true;
                        continue;
                    }
                }
            }
            match ingestor.ingest_chunk(*registry, *addr, next[i], head).await {
                Ok(n) => next[i] = n,
                Err(e) => {
                    tracing::warn!(registry = registry.name(), %e, "chunk ingest failed");
                    had_error = true;
                }
            }
        }

        if had_error {
            consecutive_failures += 1;
            if consecutive_failures >= 5 {
                if let Some(fb) = &fallback {
                    on_fallback = !on_fallback;
                    tracing::warn!(on_fallback, "switching rpc provider after ingest errors");
                    ingestor.provider = if on_fallback {
                        fb.clone()
                    } else {
                        primary.clone()
                    };
                    consecutive_failures = 0;
                }
            }
            tokio::time::sleep(Duration::from_secs(5)).await;
        } else {
            consecutive_failures = 0;
        }
        if all_caught_up {
            tokio::time::sleep(Duration::from_secs(10)).await;
        }
    }
}

//! Chunked log ingestion with adaptive range sizing and reorg tracking.

use crate::events::{FeedbackRevoked, NewFeedback, Registered, Transfer, URIUpdated};
use alloy::primitives::Address;
use alloy::providers::Provider;
use alloy::rpc::types::{Filter, Log};
use alloy::sol_types::SolEvent;
use anyhow::Context;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use std::collections::HashMap;
use std::future::Future;
use std::time::Duration;

/// Hard ceiling on any single rpc call. The transport has its own timeout,
/// but a hung connection must never stall ingestion for minutes.
async fn with_deadline<T, F: Future<Output = T>>(fut: F) -> anyhow::Result<T> {
    tokio::time::timeout(Duration::from_secs(45), fut)
        .await
        .map_err(|_| anyhow::anyhow!("rpc call exceeded 45s deadline"))
}

/// Confirmation depth: stay this many blocks behind head so shallow reorgs
/// never land in the database.
pub const CONFIRM_DEPTH: u64 = 15;

const MAX_CHUNK: u64 = 4_900;
const MIN_CHUNK: u64 = 50;

pub struct Ingestor<P: Provider> {
    pub provider: P,
    pub pool: PgPool,
    /// Cache of block number to timestamp for this run.
    block_times: HashMap<u64, DateTime<Utc>>,
    /// Current adaptive chunk size.
    chunk: u64,
}

#[derive(Clone, Copy, PartialEq)]
pub enum Registry {
    Identity,
    Reputation,
}

impl Registry {
    pub fn name(self) -> &'static str {
        match self {
            Registry::Identity => "identity",
            Registry::Reputation => "reputation",
        }
    }
}

impl<P: Provider> Ingestor<P> {
    pub fn new(provider: P, pool: PgPool) -> Self {
        Self {
            provider,
            pool,
            block_times: HashMap::new(),
            chunk: MAX_CHUNK,
        }
    }

    /// Resume point for a registry: the stored state row, or its deploy block.
    pub async fn start_block(&self, address: Address, deploy_block: u64) -> anyhow::Result<u64> {
        let row: Option<(i64,)> =
            sqlx::query_as("select last_block from indexer_state where registry = $1")
                .bind(address.as_slice())
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|(b,)| b as u64 + 1).unwrap_or(deploy_block))
    }

    pub async fn save_state(
        &self,
        address: Address,
        block: u64,
        block_hash: &[u8],
    ) -> anyhow::Result<()> {
        sqlx::query(
            "insert into indexer_state (registry, last_block, last_block_hash, updated_at)
             values ($1, $2, $3, now())
             on conflict (registry) do update
             set last_block = excluded.last_block,
                 last_block_hash = excluded.last_block_hash,
                 updated_at = now()",
        )
        .bind(address.as_slice())
        .bind(block as i64)
        .bind(block_hash)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Detect a reorg: the stored hash for last_block no longer matches the
    /// chain. Returns the block to rewind to when it happens.
    pub async fn check_reorg(&self, address: Address) -> anyhow::Result<Option<u64>> {
        let row: Option<(i64, Vec<u8>)> = sqlx::query_as(
            "select last_block, last_block_hash from indexer_state where registry = $1",
        )
        .bind(address.as_slice())
        .fetch_optional(&self.pool)
        .await?;
        let Some((block, stored_hash)) = row else {
            return Ok(None);
        };
        let on_chain = with_deadline(async {
            self.provider
                .get_block_by_number((block as u64).into())
                .await
        })
        .await??;
        match on_chain {
            Some(b) if b.header.hash.as_slice() == stored_hash.as_slice() => Ok(None),
            _ => Ok(Some((block as u64).saturating_sub(100))),
        }
    }

    /// Ingest one adaptive chunk starting at `from`, not exceeding `head`.
    /// Returns the next start block.
    pub async fn ingest_chunk(
        &mut self,
        registry: Registry,
        address: Address,
        from: u64,
        head: u64,
    ) -> anyhow::Result<u64> {
        let to = (from + self.chunk - 1).min(head);
        let filter = Filter::new().address(address).from_block(from).to_block(to);
        let logs = match with_deadline(self.provider.get_logs(&filter))
            .await
            .unwrap_or_else(|e| {
                Err(alloy::transports::TransportErrorKind::custom_str(
                    &e.to_string(),
                ))
            }) {
            Ok(logs) => {
                // Grow slowly after success, halve on failure.
                self.chunk = (self.chunk + self.chunk / 4).min(MAX_CHUNK);
                logs
            }
            Err(e) => {
                let old = self.chunk;
                self.chunk = (self.chunk / 2).max(MIN_CHUNK);
                tracing::warn!(%e, from, to, old_chunk = old, new_chunk = self.chunk,
                    "get_logs failed, halving chunk");
                return Ok(from);
            }
        };

        for log in &logs {
            self.apply_log(registry, log)
                .await
                .with_context(|| format!("applying log at block {:?}", log.block_number))?;
        }

        let boundary = with_deadline(async { self.provider.get_block_by_number(to.into()).await })
            .await??
            .context("boundary block missing")?;
        self.save_state(address, to, boundary.header.hash.as_slice())
            .await?;
        tracing::info!(
            registry = registry.name(),
            from,
            to,
            logs = logs.len(),
            "chunk ingested"
        );
        Ok(to + 1)
    }

    async fn block_time(&mut self, number: u64) -> anyhow::Result<DateTime<Utc>> {
        if let Some(t) = self.block_times.get(&number) {
            return Ok(*t);
        }
        let block = with_deadline(async { self.provider.get_block_by_number(number.into()).await })
            .await??
            .with_context(|| format!("block {number} missing"))?;
        let t = DateTime::from_timestamp(block.header.timestamp as i64, 0)
            .context("timestamp out of range")?;
        // Keep the cache bounded; ingestion moves forward so old entries die.
        if self.block_times.len() > 50_000 {
            self.block_times.clear();
        }
        self.block_times.insert(number, t);
        Ok(t)
    }

    async fn apply_log(&mut self, registry: Registry, log: &Log) -> anyhow::Result<()> {
        let block_number = log.block_number.context("log without block number")?;
        let log_index = log.log_index.context("log without index")? as i32;
        let tx_hash = log.transaction_hash.context("log without tx hash")?;
        let topic0 = match log.topic0() {
            Some(t) => *t,
            None => return Ok(()),
        };

        match registry {
            Registry::Identity => {
                if topic0 == Registered::SIGNATURE_HASH {
                    let ev = log.log_decode::<Registered>()?.inner.data;
                    let agent_id = ev.agentId;
                    let time = self.block_time(block_number).await?;
                    sqlx::query(
                        "insert into agents (agent_id, owner, token_uri, registered_block, registered_at, last_seen_block)
                         values ($1::numeric, $2, $3, $4, $5, $4)
                         on conflict (agent_id) do update
                         set owner = excluded.owner,
                             token_uri = excluded.token_uri,
                             last_seen_block = greatest(agents.last_seen_block, excluded.last_seen_block)",
                    )
                    .bind(agent_id.to_string())
                    .bind(ev.owner.as_slice())
                    .bind(&ev.agentURI)
                    .bind(block_number as i64)
                    .bind(time)
                    .execute(&self.pool)
                    .await?;
                } else if topic0 == URIUpdated::SIGNATURE_HASH {
                    let ev = log.log_decode::<URIUpdated>()?.inner.data;
                    let agent_id = ev.agentId;
                    sqlx::query(
                        "update agents
                         set token_uri = $2, card_fetched_at = null, last_seen_block = $3
                         where agent_id = $1::numeric",
                    )
                    .bind(agent_id.to_string())
                    .bind(&ev.newURI)
                    .bind(block_number as i64)
                    .execute(&self.pool)
                    .await?;
                } else if topic0 == Transfer::SIGNATURE_HASH {
                    let ev = log.log_decode::<Transfer>()?.inner.data;
                    let (to_addr, token_id) = (ev.to, ev.tokenId);
                    // Mints are handled by Registered; transfers move ownership.
                    if to_addr != Address::ZERO {
                        sqlx::query(
                            "update agents set owner = $2, last_seen_block = $3 where agent_id = $1::numeric",
                        )
                        .bind(token_id.to_string())
                        .bind(to_addr.as_slice())
                        .bind(block_number as i64)
                        .execute(&self.pool)
                        .await?;
                    }
                }
            }
            Registry::Reputation => {
                if topic0 == NewFeedback::SIGNATURE_HASH {
                    let ev = log.log_decode::<NewFeedback>()?.inner.data;
                    let (agent_id, reviewer) = (ev.agentId, ev.clientAddress);
                    let time = self.block_time(block_number).await?;
                    let tags: Vec<String> = [ev.tag1.clone(), ev.tag2.clone()]
                        .into_iter()
                        .filter(|t| !t.is_empty())
                        .collect();
                    sqlx::query(
                        "insert into feedback
                           (agent_id, reviewer, feedback_index, value, value_decimals, tags,
                            endpoint, uri, feedback_hash, tx_hash, log_index, block_number, block_time)
                         values ($1::numeric, $2, $3::numeric, $4::numeric, $5, $6, $7, $8, $9, $10, $11, $12, $13)
                         on conflict (tx_hash, log_index) do nothing",
                    )
                    .bind(agent_id.to_string())
                    .bind(reviewer.as_slice())
                    .bind(ev.feedbackIndex.to_string())
                    .bind(ev.value.to_string())
                    .bind(ev.valueDecimals as i32)
                    .bind(&tags)
                    .bind(&ev.endpoint)
                    .bind(&ev.feedbackURI)
                    .bind(ev.feedbackHash.as_slice())
                    .bind(tx_hash.as_slice())
                    .bind(log_index)
                    .bind(block_number as i64)
                    .bind(time)
                    .execute(&self.pool)
                    .await?;
                } else if topic0 == FeedbackRevoked::SIGNATURE_HASH {
                    let ev = log.log_decode::<FeedbackRevoked>()?.inner.data;
                    let (agent_id, reviewer, feedback_index) =
                        (ev.agentId, ev.clientAddress, ev.feedbackIndex);
                    sqlx::query(
                        "update feedback set revoked = true, revoked_tx = $4
                         where agent_id = $1::numeric and reviewer = $2 and feedback_index = $3::numeric",
                    )
                    .bind(agent_id.to_string())
                    .bind(reviewer.as_slice())
                    .bind(feedback_index.to_string())
                    .bind(tx_hash.as_slice())
                    .execute(&self.pool)
                    .await?;
                }
            }
        }
        Ok(())
    }
}

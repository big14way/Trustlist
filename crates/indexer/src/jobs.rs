//! Follows the hire rail: every job opened through HireRail is mirrored into
//! the jobs table, then reconciled against the kernel so the UI can show the
//! real lifecycle without an archive node.
//!
//! The rail may live on a different chain from the registries during
//! development, so this follower takes its own provider and resume state.

use alloy::primitives::Address;
use alloy::providers::Provider;
use alloy::rpc::types::Filter;
use alloy::sol;
use alloy::sol_types::SolEvent;
use anyhow::Context;
use chrono::{DateTime, Utc};
use sqlx::PgPool;

sol! {
    #[derive(Debug)]
    event Hired(
        uint256 indexed jobId,
        uint256 indexed agentId,
        address indexed hirer,
        address provider,
        uint256 budget,
        uint64 deadline,
        bytes32 specHash,
        uint8 mode
    );

    #[derive(Debug)]
    event Settled(uint256 indexed jobId, address indexed caller);

    #[derive(Debug)]
    event Accepted(uint256 indexed jobId, address indexed hirer, uint256 paid);

    #[derive(Debug)]
    event WorkRejected(uint256 indexed jobId, address indexed hirer, uint256 refunded);

    #[derive(Debug)]
    event Reclaimed(uint256 indexed jobId, address indexed hirer, uint256 refunded);
}

sol! {
    #[sol(rpc)]
    interface IKernelView {
        struct Job {
            uint256 id;
            address client;
            address provider;
            address evaluator;
            string description;
            uint256 budget;
            uint256 expiredAt;
            uint8 status;
            address hook;
            uint256 submittedAt;
            bytes32 deliverable;
        }
        function getJob(uint256 jobId) external view returns (Job memory);
        function paymentToken() external view returns (address);
    }
}

/// Kernel job status, as the ERC-8183 kernel defines it.
fn state_name(status: u8) -> &'static str {
    match status {
        0 => "open",
        1 => "funded",
        2 => "submitted",
        3 => "completed",
        4 => "rejected",
        5 => "expired",
        _ => "unknown",
    }
}

pub struct JobFollower<P: Provider + Clone> {
    pub provider: P,
    pub pool: PgPool,
    pub rail: Address,
    pub kernel: Address,
    pub chain_id: u64,
}

impl<P: Provider + Clone> JobFollower<P> {
    pub async fn start_block(&self, deploy_block: u64) -> anyhow::Result<u64> {
        let row: Option<(i64,)> =
            sqlx::query_as("select last_block from rail_state where rail = $1")
                .bind(self.rail.as_slice())
                .fetch_optional(&self.pool)
                .await?;
        Ok(row.map(|(b,)| b as u64 + 1).unwrap_or(deploy_block))
    }

    async fn save_state(&self, block: u64) -> anyhow::Result<()> {
        sqlx::query(
            "insert into rail_state (rail, chain_id, last_block, updated_at)
             values ($1, $2, $3, now())
             on conflict (rail) do update
             set last_block = excluded.last_block, updated_at = now()",
        )
        .bind(self.rail.as_slice())
        .bind(self.chain_id as i64)
        .bind(block as i64)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Ingest rail logs in [from, to] and return the next start block.
    pub async fn ingest(&mut self, from: u64, to: u64) -> anyhow::Result<u64> {
        let filter = Filter::new()
            .address(self.rail)
            .from_block(from)
            .to_block(to);
        let logs = self.provider.get_logs(&filter).await?;
        for log in &logs {
            let Some(topic0) = log.topic0() else { continue };
            let block_number = log.block_number.context("log without block")?;
            let tx = log.transaction_hash.context("log without tx hash")?;
            let time = self.block_time(block_number).await?;

            if *topic0 == Hired::SIGNATURE_HASH {
                let ev = log.log_decode::<Hired>()?.inner.data;
                let deadline = DateTime::from_timestamp(ev.deadline as i64, 0)
                    .context("deadline out of range")?;
                // 0 is Direct, 1 is Protected, matching HireRail.Mode.
                let mode = if ev.mode == 1 { "protected" } else { "direct" };
                sqlx::query(
                    "insert into jobs (job_id, agent_id, hirer, provider, token, budget,
                                       spec_hash, state, created_at, deadline, create_tx,
                                       chain_id, rail, kernel_status, mode)
                     values ($1::numeric, $2::numeric, $3, $4, $5, $6::numeric, $7, 'funded',
                             $8, $9, $10, $11, $12, 1, $13)
                     on conflict (job_id) do nothing",
                )
                .bind(ev.jobId.to_string())
                .bind(ev.agentId.to_string())
                .bind(ev.hirer.as_slice())
                .bind(ev.provider.as_slice())
                .bind(self.payment_token().await?.as_slice().to_vec())
                .bind(ev.budget.to_string())
                .bind(ev.specHash.as_slice())
                .bind(time)
                .bind(deadline)
                .bind(tx.as_slice())
                .bind(self.chain_id as i64)
                .bind(self.rail.as_slice())
                .bind(mode)
                .execute(&self.pool)
                .await?;
                tracing::info!(job_id = %ev.jobId, agent_id = %ev.agentId, mode, "job hired");
            } else if *topic0 == Settled::SIGNATURE_HASH {
                let ev = log.log_decode::<Settled>()?.inner.data;
                sqlx::query(
                    "update jobs set settle_tx = $2, settled_at = $3 where job_id = $1::numeric",
                )
                .bind(ev.jobId.to_string())
                .bind(tx.as_slice())
                .bind(time)
                .execute(&self.pool)
                .await?;
            } else if *topic0 == Accepted::SIGNATURE_HASH
                || *topic0 == WorkRejected::SIGNATURE_HASH
            {
                // Direct mode settles through Accepted or WorkRejected rather
                // than Settled, and those were not recorded, so every direct
                // job on the site was missing its settle link while the
                // kernel reported it complete. The state itself still comes
                // from the kernel in reconcile; this only records which
                // transaction did it.
                let job_id = if *topic0 == Accepted::SIGNATURE_HASH {
                    log.log_decode::<Accepted>()?.inner.data.jobId
                } else {
                    log.log_decode::<WorkRejected>()?.inner.data.jobId
                };
                sqlx::query(
                    "update jobs set settle_tx = $2, settled_at = $3 where job_id = $1::numeric",
                )
                .bind(job_id.to_string())
                .bind(tx.as_slice())
                .bind(time)
                .execute(&self.pool)
                .await?;
            } else if *topic0 == Reclaimed::SIGNATURE_HASH {
                let ev = log.log_decode::<Reclaimed>()?.inner.data;
                sqlx::query(
                    "update jobs set state = 'expired', refunded = $2::numeric,
                                     settle_tx = $3, settled_at = $4, kernel_status = 5
                     where job_id = $1::numeric",
                )
                .bind(ev.jobId.to_string())
                .bind(ev.refunded.to_string())
                .bind(tx.as_slice())
                .bind(time)
                .execute(&self.pool)
                .await?;
                tracing::info!(job_id = %ev.jobId, "escrow reclaimed by hirer");
            }
        }
        self.save_state(to).await?;
        Ok(to + 1)
    }

    async fn payment_token(&self) -> anyhow::Result<Address> {
        let kernel = IKernelView::new(self.kernel, self.provider.clone());
        Ok(kernel.paymentToken().call().await?)
    }

    async fn block_time(&self, number: u64) -> anyhow::Result<DateTime<Utc>> {
        let block = self
            .provider
            .get_block_by_number(number.into())
            .await?
            .context("block missing")?;
        DateTime::from_timestamp(block.header.timestamp as i64, 0).context("timestamp out of range")
    }

    /// Re-read every job that has not reached a terminal state and write the
    /// kernel's own view of it back. This is what turns "funded" into
    /// "submitted" and then "completed" without needing an event for each.
    pub async fn reconcile(&self) -> anyhow::Result<u64> {
        let open: Vec<(String,)> = sqlx::query_as(
            "select job_id::text from jobs
             where chain_id = $1 and state not in ('completed','rejected','expired')
             order by job_id desc limit 200",
        )
        .bind(self.chain_id as i64)
        .fetch_all(&self.pool)
        .await?;

        let kernel = IKernelView::new(self.kernel, self.provider.clone());
        let mut changed = 0u64;
        for (job_id,) in open {
            let id: alloy::primitives::U256 = job_id.parse().context("job id")?;
            let job = match kernel.getJob(id).call().await {
                Ok(j) => j,
                Err(e) => {
                    tracing::warn!(job_id, %e, "getJob failed");
                    continue;
                }
            };
            let submitted_at = if job.submittedAt > alloy::primitives::U256::ZERO {
                DateTime::from_timestamp(job.submittedAt.to::<u64>() as i64, 0)
            } else {
                None
            };
            let result = sqlx::query(
                "update jobs set state = $2, kernel_status = $3, submitted_at = $4,
                                 deliverable = $5, last_synced_at = now()
                 where job_id = $1::numeric and state is distinct from $2",
            )
            .bind(&job_id)
            .bind(state_name(job.status))
            .bind(job.status as i32)
            .bind(submitted_at)
            .bind(job.deliverable.as_slice())
            .execute(&self.pool)
            .await?;
            if result.rows_affected() > 0 {
                changed += 1;
                tracing::info!(job_id, state = state_name(job.status), "job state advanced");
            }
        }
        Ok(changed)
    }
}

//! Registry log ingestion. The backfill and head follower land in M1; at M0
//! this binary proves configuration and database wiring, then exits cleanly.

use common::config::Config;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    common::init_tracing("indexer");
    let config = Config::from_env()?;
    let _pool = common::connect_and_migrate(&config.database_url).await?;
    tracing::info!(
        registry = %config.identity_registry,
        "config and database verified; ingestion ships in M1, exiting"
    );
    Ok(())
}

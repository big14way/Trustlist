//! Trust engine. Reviewer weighting and scoring land in M5; at M0 this
//! binary proves configuration and database wiring, then exits cleanly.

use common::config::Config;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    common::init_tracing("trust");
    let config = Config::from_env()?;
    let _pool = common::connect_and_migrate(&config.database_url).await?;
    tracing::info!(
        reputation_registry = %config.reputation_registry,
        "config and database verified; scoring ships in M5, exiting"
    );
    Ok(())
}

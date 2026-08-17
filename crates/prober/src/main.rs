//! Endpoint liveness prober. Card resolution and probing land in M2; at M0
//! this binary proves configuration and database wiring, then exits cleanly.

use common::config::Config;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    common::init_tracing("prober");
    let config = Config::from_env()?;
    let _pool = common::connect_and_migrate(&config.database_url).await?;
    tracing::info!(
        concurrency = config.probe_concurrency,
        interval_secs = config.probe_interval_secs,
        "config and database verified; probing ships in M2, exiting"
    );
    Ok(())
}

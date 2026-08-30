//! Shared configuration, database pool, and startup helpers for every
//! TrustList service.

pub mod config;
pub mod methodology;
pub mod snapshot;

use anyhow::Context;
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;

/// Connect to Postgres and run pending migrations from /migrations.
pub async fn connect_and_migrate(database_url: &str) -> anyhow::Result<PgPool> {
    let pool = PgPoolOptions::new()
        .max_connections(8)
        .connect(database_url)
        .await
        .context("connecting to postgres")?;
    sqlx::migrate!("../../migrations")
        .run(&pool)
        .await
        .context("running migrations")?;
    Ok(pool)
}

/// Handle `--version` and exit, before anything touches the network or the
/// database.
///
/// Every service calls this first. It exists so a downloaded binary can be
/// proved to run on this machine without starting it: a mismatched glibc
/// fails at the dynamic loader, and the only way to find that out is to
/// execute the thing. Without a flag that returns immediately, the only way
/// to test would be to boot a server and kill it.
///
/// The commit is stamped in at build time when TRUSTLIST_COMMIT is set, which
/// is how a prebuilt binary can be checked against the source it claims to
/// be. Locally it is absent and the version says so.
pub fn handle_version_flag(service: &str) {
    if std::env::args().any(|a| a == "--version" || a == "-V") {
        println!(
            "{service} {} ({})",
            env!("CARGO_PKG_VERSION"),
            option_env!("TRUSTLIST_COMMIT").unwrap_or("source build")
        );
        std::process::exit(0);
    }
}

/// Initialise structured logging. RUST_LOG overrides the default level.
pub fn init_tracing(service: &str) {
    use tracing_subscriber::EnvFilter;
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    tracing_subscriber::fmt().with_env_filter(filter).init();
    tracing::info!(service, "starting");
}

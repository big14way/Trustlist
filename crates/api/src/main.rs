//! TrustList REST API. M1 serves health, agents, and stats. Scores, jobs,
//! snapshots, and SSE arrive with their milestones.

mod routes;

use axum::routing::get;
use axum::Router;
use common::config::Config;
use sqlx::PgPool;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    common::init_tracing("api");
    let config = Config::from_env()?;
    let pool = common::connect_and_migrate(&config.database_url).await?;

    let app = Router::new()
        .route("/v1/health", get(routes::health))
        .route("/v1/agents", get(routes::list_agents))
        .route("/v1/agents/{id}", get(routes::get_agent))
        .route("/v1/stats", get(routes::stats))
        .with_state(AppState { pool })
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http());

    let addr = format!("0.0.0.0:{}", config.api_port);
    tracing::info!(%addr, "listening");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

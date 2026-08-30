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
    common::handle_version_flag("api");
    common::init_tracing("api");
    let config = Config::from_env()?;
    let pool = common::connect_and_migrate(&config.database_url).await?;

    let app = Router::new()
        .route("/v1/health", get(routes::health))
        .route("/v1/agents", get(routes::list_agents))
        .route("/v1/agents/{id}", get(routes::get_agent))
        .route("/v1/agents/{id}/uptime", get(routes::agent_uptime))
        .route("/v1/agents/{id}/reviews", get(routes::agent_reviews))
        .route("/v1/agents/{id}/endpoints", get(routes::agent_endpoints))
        .route("/v1/agents/{id}/jobs", get(routes::list_jobs))
        .route("/v1/jobs", get(routes::list_jobs))
        .route("/v1/jobs/{id}", get(routes::get_job))
        .route("/v1/stats", get(routes::stats))
        .route("/v1/methodology", get(routes::methodology))
        .route("/v1/uptime", get(routes::bulk_uptime))
        .route("/v1/snapshots/latest", get(routes::latest_snapshot))
        .route("/v1/snapshots/published", get(routes::published_snapshot))
        .route(
            "/v1/snapshots/{id}/proof/{agent_id}",
            get(routes::snapshot_proof),
        )
        .with_state(AppState { pool })
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http());

    let addr = format!("0.0.0.0:{}", config.api_port);
    tracing::info!(%addr, "listening");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

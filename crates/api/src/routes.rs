//! Route handlers. Every number here is a database read; nothing is invented.

use crate::AppState;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use serde::Deserialize;
use serde_json::json;
use sqlx::Row;

pub async fn health(State(state): State<AppState>) -> impl IntoResponse {
    let db_ok = sqlx::query("select 1").execute(&state.pool).await.is_ok();
    let status = if db_ok {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };
    (
        status,
        Json(json!({ "status": if db_ok { "ok" } else { "degraded" }, "db": db_ok })),
    )
}

#[derive(Deserialize)]
pub struct ListParams {
    pub q: Option<String>,
    pub category: Option<String>,
    pub status: Option<String>,
    pub sort: Option<String>,
    pub cursor: Option<String>,
    pub limit: Option<i64>,
}

/// M1 status derivation, before probe history exists: an agent with at least
/// one declared endpoint is "measuring" (we have not probed 24 times yet),
/// anything else is "dormant" (no valid endpoint ever seen). Live, flaky,
/// and down require probe data and appear in M2.
const STATUS_SQL: &str = "case
    when a.endpoints is not null and jsonb_array_length(a.endpoints) > 0 then 'measuring'
    else 'dormant'
  end";

fn agent_row_to_json(row: &sqlx::postgres::PgRow) -> serde_json::Value {
    let owner: Vec<u8> = row.get("owner");
    json!({
        "agent_id": row.get::<String, _>("agent_id"),
        "name": row.get::<Option<String>, _>("name"),
        "description": row.get::<Option<String>, _>("description"),
        "categories": row.get::<Vec<String>, _>("categories"),
        "status": row.get::<String, _>("status"),
        "card_status": row.get::<Option<String>, _>("card_status"),
        "endpoints": row.get::<Option<serde_json::Value>, _>("endpoints"),
        "owner": format!("0x{}", hex_lower(&owner)),
        "registered_at": row.get::<chrono::DateTime<chrono::Utc>, _>("registered_at").to_rfc3339(),
        "registered_block": row.get::<i64, _>("registered_block"),
        "token_uri_scheme": row.get::<Option<String>, _>("token_uri_scheme"),
        // Scoring fields exist in the contract from M1 so clients can rely
        // on the shape; they hold null until the engines ship (M2, M5).
        "liveness": serde_json::Value::Null,
        "uptime_7d": serde_json::Value::Null,
        "trust": serde_json::Value::Null,
        "trust_confidence": serde_json::Value::Null,
        "feedback_total": row.get::<i64, _>("feedback_total"),
        "feedback_kept": serde_json::Value::Null,
        "jobs_completed": 0,
        "jobs_disputed": 0,
    })
}

fn hex_lower(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub async fn list_agents(
    State(state): State<AppState>,
    Query(params): Query<ListParams>,
) -> Result<impl IntoResponse, StatusCode> {
    let limit = params.limit.unwrap_or(24).clamp(1, 100);
    // Cursor is the last agent_id seen, keyset pagination on the sort order.
    let cursor_id = params.cursor.as_deref().and_then(|c| c.parse::<i64>().ok());
    let sort = params.sort.as_deref().unwrap_or("newest");

    let mut wheres = vec!["true".to_owned()];
    let mut binds: Vec<String> = Vec::new();
    if let Some(q) = &params.q {
        binds.push(format!("%{}%", q.replace(['%', '_'], "")));
        wheres.push(format!(
            "(a.name ilike ${0} or a.description ilike ${0})",
            binds.len()
        ));
    }
    if let Some(cat) = &params.category {
        binds.push(cat.clone());
        wheres.push(format!("${} = any(a.categories)", binds.len()));
    }
    if let Some(status) = &params.status {
        binds.push(status.clone());
        wheres.push(format!("({STATUS_SQL}) = ${}", binds.len()));
    }

    let order = match sort {
        "newest" => "a.registered_block desc, a.agent_id desc",
        "oldest" => "a.registered_block asc, a.agent_id asc",
        _ => "a.registered_block desc, a.agent_id desc",
    };
    let cursor_clause = if cursor_id.is_some() {
        binds.push(cursor_id.unwrap_or_default().to_string());
        if sort == "oldest" {
            format!("a.agent_id > ${}::numeric", binds.len())
        } else {
            format!("a.agent_id < ${}::numeric", binds.len())
        }
    } else {
        "true".to_owned()
    };

    let sql = format!(
        "select a.agent_id::text as agent_id, a.owner, a.name, a.description, a.categories,
                a.card_status, a.endpoints, a.registered_at, a.registered_block,
                {STATUS_SQL} as status,
                split_part(a.token_uri, ':', 1) as token_uri_scheme,
                coalesce(f.cnt, 0) as feedback_total
         from agents a
         left join (select agent_id, count(*) as cnt from feedback where not revoked group by agent_id) f
           using (agent_id)
         where {} and {}
         order by {}
         limit {}",
        wheres.join(" and "),
        cursor_clause,
        order,
        limit
    );

    let mut query = sqlx::query(&sql);
    for b in &binds {
        query = query.bind(b);
    }
    let rows = query.fetch_all(&state.pool).await.map_err(|e| {
        tracing::error!(%e, "list_agents query failed");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let total_unfiltered: i64 = sqlx::query_scalar("select count(*) from agents")
        .fetch_one(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let items: Vec<serde_json::Value> = rows.iter().map(agent_row_to_json).collect();
    let next_cursor = if items.len() as i64 == limit {
        rows.last().map(|r| r.get::<String, _>("agent_id"))
    } else {
        None
    };
    Ok(Json(json!({
        "items": items,
        "next_cursor": next_cursor,
        "total_unfiltered": total_unfiltered,
    })))
}

pub async fn get_agent(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<impl IntoResponse, StatusCode> {
    let clean: String = id.chars().filter(|c| c.is_ascii_digit()).collect();
    if clean.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    let sql = format!(
        "select a.agent_id::text as agent_id, a.owner, a.name, a.description, a.categories,
                a.card_status, a.endpoints, a.registered_at, a.registered_block,
                {STATUS_SQL} as status,
                split_part(a.token_uri, ':', 1) as token_uri_scheme,
                coalesce(f.cnt, 0) as feedback_total
         from agents a
         left join (select agent_id, count(*) as cnt from feedback where not revoked group by agent_id) f
           using (agent_id)
         where a.agent_id = $1::numeric"
    );
    let row = sqlx::query(&sql)
        .bind(&clean)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(agent_row_to_json(&row)))
}

pub async fn stats(State(state): State<AppState>) -> Result<impl IntoResponse, StatusCode> {
    let row = sqlx::query(
        "select
           (select count(*) from agents) as registered,
           (select count(*) from agents where card_status = 'ok') as cards_ok,
           (select count(*) from agents where endpoints is not null and jsonb_array_length(endpoints) > 0) as with_endpoints,
           (select count(*) from agents where card_fetched_at is not null) as cards_fetched,
           (select count(*) from feedback where not revoked) as feedback,
           (select count(distinct reviewer) from feedback) as reviewers,
           (select max(last_block) from indexer_state) as indexed_to_block,
           (select max(updated_at) from indexer_state) as indexed_at",
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(%e, "stats query failed");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(json!({
        "registered": row.get::<i64, _>("registered"),
        "cards_ok": row.get::<i64, _>("cards_ok"),
        "with_endpoints": row.get::<i64, _>("with_endpoints"),
        "cards_fetched": row.get::<i64, _>("cards_fetched"),
        "feedback": row.get::<i64, _>("feedback"),
        "reviewers": row.get::<i64, _>("reviewers"),
        "indexed_to_block": row.get::<Option<i64>, _>("indexed_to_block"),
        "indexed_at": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("indexed_at")
            .map(|t| t.to_rfc3339()),
    })))
}

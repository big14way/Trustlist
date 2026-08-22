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

/// Status comes from the latest scoring run where one exists. Agents that
/// have never been scored are measuring (endpoint declared, probes pending)
/// or dormant (no valid endpoint ever seen).
const STATUS_SQL: &str = "coalesce(sc.status, case
    when a.endpoints is not null and jsonb_array_length(a.endpoints) > 0 then 'measuring'
    else 'dormant'
  end)";

/// Latest score row per agent, joined laterally.
const SCORE_JOIN: &str = "left join lateral (
    select * from agent_scores x
    where x.agent_id = a.agent_id
    order by computed_at desc limit 1
  ) sc on true";

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
        // Liveness fields come from the latest scoring run; trust stays
        // null until the M5 engine ships. Nothing fabricates a score.
        "liveness": row.get::<Option<sqlx::types::BigDecimal>, _>("liveness").map(|v| v.to_string()),
        "uptime_7d": row.get::<Option<sqlx::types::BigDecimal>, _>("uptime_7d").map(|v| v.to_string()),
        "median_latency_ms": row.get::<Option<i32>, _>("median_latency"),
        "probes_7d": row.get::<Option<i32>, _>("probes_7d"),
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
        // Comma separated lists are allowed: status=live,flaky is the
        // default marketplace filter per SPEC.md Section 13 step 4.
        let list: Vec<String> = status
            .split(',')
            .map(|s| s.trim().to_ascii_lowercase())
            .filter(|s| !s.is_empty())
            .collect();
        binds.push(list.join(","));
        wheres.push(format!(
            "({STATUS_SQL}) = any(string_to_array(${}, ','))",
            binds.len()
        ));
    }

    let order = match sort {
        "newest" => "a.registered_block desc, a.agent_id desc",
        "oldest" => "a.registered_block asc, a.agent_id asc",
        "uptime" => "sc.uptime_7d desc nulls last, a.agent_id desc",
        _ => "sc.rank_score desc nulls last, a.agent_id desc",
    };
    // Keyset cursors only apply to the id ordered sorts; rank and uptime
    // sorted pages fall back to plain offset free first page semantics.
    let cursor_clause = if cursor_id.is_some() && (sort == "newest" || sort == "oldest") {
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
                sc.liveness, sc.uptime_7d, sc.median_latency, sc.probes_7d,
                split_part(a.token_uri, ':', 1) as token_uri_scheme,
                coalesce(f.cnt, 0) as feedback_total
         from agents a
         {SCORE_JOIN}
         left join (select agent_id, count(*) as cnt from feedback where not revoked group by agent_id) f
           on f.agent_id = a.agent_id
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
                sc.liveness, sc.uptime_7d, sc.median_latency, sc.probes_7d,
                split_part(a.token_uri, ':', 1) as token_uri_scheme,
                coalesce(f.cnt, 0) as feedback_total
         from agents a
         {SCORE_JOIN}
         left join (select agent_id, count(*) as cnt from feedback where not revoked group by agent_id) f
           on f.agent_id = a.agent_id
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
           (select count(*) from (select distinct on (agent_id) status from agent_scores order by agent_id, computed_at desc) t where t.status = 'live') as live,
           (select count(*) from (select distinct on (agent_id) status from agent_scores order by agent_id, computed_at desc) t where t.status = 'flaky') as flaky,
           (select count(*) from (select distinct on (agent_id) status from agent_scores order by agent_id, computed_at desc) t where t.status = 'down') as down,
           (select count(*) from (select distinct on (agent_id) status from agent_scores order by agent_id, computed_at desc) t where t.status = 'measuring') as measuring,
           (select count(*) from probe_results) as probes_total,
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
        "live": row.get::<i64, _>("live"),
        "flaky": row.get::<i64, _>("flaky"),
        "down": row.get::<i64, _>("down"),
        "measuring": row.get::<i64, _>("measuring"),
        "probes_total": row.get::<i64, _>("probes_total"),
        "indexed_to_block": row.get::<Option<i64>, _>("indexed_to_block"),
        "indexed_at": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("indexed_at")
            .map(|t| t.to_rfc3339()),
    })))
}

/// 168 hourly buckets for the probe strip: per hour, the share of probes
/// that succeeded, or null where no probe ran.
pub async fn agent_uptime(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<impl IntoResponse, StatusCode> {
    let clean: String = id.chars().filter(|c| c.is_ascii_digit()).collect();
    if clean.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    let rows: Vec<(chrono::DateTime<chrono::Utc>, Option<f64>, i64)> = sqlx::query_as(
        "with observer_outage as (
           select date_trunc('hour', probed_at) as h from probe_results
           where probed_at > now() - interval '7 days'
           group by 1 having count(*) > 100 and avg(ok::int) < 0.05
         )
         select h.hour,
                case when h.hour in (select h from observer_outage) then null
                     else avg(pr.ok::int)::float8 end,
                case when h.hour in (select h from observer_outage) then 0
                     else count(pr.id) end
         from generate_series(
                date_trunc('hour', now()) - interval '167 hours',
                date_trunc('hour', now()), interval '1 hour') h(hour)
         left join probe_results pr
           on pr.agent_id = $1::numeric
          and pr.probed_at >= h.hour and pr.probed_at < h.hour + interval '1 hour'
         group by h.hour order by h.hour",
    )
    .bind(&clean)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(%e, "uptime query failed");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;
    let buckets: Vec<serde_json::Value> = rows
        .iter()
        .map(|(hour, ok_share, probes)| {
            json!({
                "hour": hour.to_rfc3339(),
                "ok_share": ok_share,
                "probes": probes,
            })
        })
        .collect();
    Ok(Json(json!({ "agent_id": clean, "buckets": buckets })))
}

#[derive(Deserialize)]
pub struct BulkUptimeParams {
    pub ids: String,
}

/// Bulk probe strips: one request returns the 168 hourly buckets for up to
/// one hundred agents, keyed by agent id.
pub async fn bulk_uptime(
    State(state): State<AppState>,
    Query(params): Query<BulkUptimeParams>,
) -> Result<impl IntoResponse, StatusCode> {
    let ids: Vec<String> = params
        .ids
        .split(',')
        .map(|p| p.chars().filter(|c| c.is_ascii_digit()).collect::<String>())
        .filter(|p| !p.is_empty())
        .take(100)
        .collect();
    if ids.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    let rows: Vec<(String, chrono::DateTime<chrono::Utc>, Option<f64>, i64)> = sqlx::query_as(
        "with observer_outage as (
           select date_trunc('hour', probed_at) as h from probe_results
           where probed_at > now() - interval '7 days'
           group by 1 having count(*) > 100 and avg(ok::int) < 0.05
         )
         select pr.agent_id::text, date_trunc('hour', pr.probed_at) as hour,
                avg(pr.ok::int)::float8, count(*)
         from probe_results pr
         where pr.agent_id = any(select unnest($1::numeric[]))
           and pr.probed_at > now() - interval '168 hours'
           and date_trunc('hour', pr.probed_at) not in (select h from observer_outage)
         group by 1, 2 order by 1, 2",
    )
    .bind(&ids)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(%e, "bulk uptime query failed");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;
    let mut map: std::collections::HashMap<String, Vec<serde_json::Value>> =
        std::collections::HashMap::new();
    for (agent_id, hour, ok_share, probes) in rows {
        map.entry(agent_id).or_default().push(json!({
            "hour": hour.to_rfc3339(),
            "ok_share": ok_share,
            "probes": probes,
        }));
    }
    Ok(Json(json!(map)))
}

/// Raw feedback for an agent, newest first. Reviewer independence weights
/// and the kept/discarded split arrive with the trust engine in M5; until
/// then this reports what the registry says and nothing more, and
/// `kept` is null rather than a guess.
pub async fn agent_reviews(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<impl IntoResponse, StatusCode> {
    let clean: String = id.chars().filter(|c| c.is_ascii_digit()).collect();
    if clean.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    let rows = sqlx::query(
        "select reviewer, value, value_decimals, tags, uri, revoked,
                block_time, tx_hash
         from feedback
         where agent_id = $1::numeric
         order by block_time desc
         limit 200",
    )
    .bind(&clean)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(%e, "reviews query failed");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let items: Vec<serde_json::Value> = rows
        .iter()
        .map(|r| {
            let reviewer: Vec<u8> = r.get("reviewer");
            let tx: Vec<u8> = r.get("tx_hash");
            let value: sqlx::types::BigDecimal = r.get("value");
            json!({
                "reviewer": format!("0x{}", hex_lower(&reviewer)),
                "value": value.to_string(),
                "value_decimals": r.get::<i32, _>("value_decimals"),
                "tags": r.get::<Vec<String>, _>("tags"),
                "uri": r.get::<Option<String>, _>("uri"),
                "revoked": r.get::<bool, _>("revoked"),
                "block_time": r.get::<chrono::DateTime<chrono::Utc>, _>("block_time").to_rfc3339(),
                "tx_hash": format!("0x{}", hex_lower(&tx)),
                // Reviewer independence weighting ships in M5.
                "weight": serde_json::Value::Null,
                "flags": serde_json::Value::Array(vec![]),
            })
        })
        .collect();

    // Distinct reviewers matters more than review count on this registry:
    // 29,511 reviews were written by 105 addresses.
    let summary = sqlx::query(
        "select count(*) as total,
                count(*) filter (where revoked) as revoked,
                count(distinct reviewer) as reviewers
         from feedback where agent_id = $1::numeric",
    )
    .bind(&clean)
    .fetch_one(&state.pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(json!({
        "agent_id": clean,
        "total": summary.get::<i64, _>("total"),
        "revoked": summary.get::<i64, _>("revoked"),
        "distinct_reviewers": summary.get::<i64, _>("reviewers"),
        "kept": serde_json::Value::Null,
        "items": items,
    })))
}

/// Per endpoint probe state for an agent: what we last saw at each declared
/// URL, plus its rolling success rate. This is what turns "the agent is
/// down" into "this specific endpoint times out after 8s".
pub async fn agent_endpoints(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<impl IntoResponse, StatusCode> {
    let clean: String = id.chars().filter(|c| c.is_ascii_digit()).collect();
    if clean.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    let rows = sqlx::query(
        "select s.endpoint_url, s.kind, s.cadence_secs, s.next_due,
                last.probed_at, last.ok, last.http_status, last.latency_ms,
                last.failure_kind,
                agg.probes, agg.ok_count
         from probe_schedule s
         left join lateral (
           select probed_at, ok, http_status, latency_ms, failure_kind
           from probe_results r
           where r.agent_id = s.agent_id and r.endpoint_url = s.endpoint_url
           order by probed_at desc limit 1
         ) last on true
         left join lateral (
           select count(*) as probes, count(*) filter (where ok) as ok_count
           from probe_results r
           where r.agent_id = s.agent_id and r.endpoint_url = s.endpoint_url
             and r.probed_at > now() - interval '7 days'
         ) agg on true
         where s.agent_id = $1::numeric
         order by s.kind, s.endpoint_url",
    )
    .bind(&clean)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(%e, "endpoints query failed");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let items: Vec<serde_json::Value> = rows
        .iter()
        .map(|r| {
            let probes = r.get::<Option<i64>, _>("probes").unwrap_or(0);
            let ok_count = r.get::<Option<i64>, _>("ok_count").unwrap_or(0);
            json!({
                "url": r.get::<String, _>("endpoint_url"),
                "kind": r.get::<String, _>("kind"),
                "cadence_secs": r.get::<i32, _>("cadence_secs"),
                "last_probed_at": r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("probed_at")
                    .map(|t| t.to_rfc3339()),
                "last_ok": r.get::<Option<bool>, _>("ok"),
                "last_http_status": r.get::<Option<i32>, _>("http_status"),
                "last_latency_ms": r.get::<Option<i32>, _>("latency_ms"),
                "last_failure_kind": r.get::<Option<String>, _>("failure_kind"),
                "probes_7d": probes,
                "ok_7d": ok_count,
            })
        })
        .collect();

    Ok(Json(json!({ "agent_id": clean, "items": items })))
}

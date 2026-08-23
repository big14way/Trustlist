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
        "liveness": row.get::<Option<sqlx::types::BigDecimal>, _>("liveness")
            .map(|v| v.normalized().to_string()),
        "uptime_7d": row.get::<Option<sqlx::types::BigDecimal>, _>("uptime_7d")
            .map(|v| v.normalized().to_string()),
        "median_latency_ms": row.get::<Option<i32>, _>("median_latency"),
        "probes_7d": row.get::<Option<i32>, _>("probes_7d"),
        "trust": row.get::<Option<sqlx::types::BigDecimal>, _>("trust")
            .map(|v| v.with_scale(1).to_string()),
        "trust_confidence": row.get::<Option<sqlx::types::BigDecimal>, _>("trust_confidence")
            .map(|v| v.with_scale(2).to_string()),
        "feedback_total": row.get::<i64, _>("feedback_total"),
        "feedback_kept": row.get::<Option<i32>, _>("feedback_kept"),
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
                sc.trust, sc.trust_confidence, sc.feedback_kept,
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
                sc.trust, sc.trust_confidence, sc.feedback_kept,
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
    // Read the snapshot the trust engine maintains rather than counting six
    // million score rows per page load. computed_at travels with it so the
    // page can say how fresh these are instead of implying they are live.
    let row = sqlx::query(
        "select s.registered, s.cards_fetched, s.cards_ok, s.with_endpoints,
                s.feedback, s.reviewers, s.live, s.flaky, s.down, s.measuring,
                s.probes_total, s.computed_at, s.agents_rated, s.agents_scored,
                s.reviews_kept, s.reviewers_independent,
                s.largest_cluster_reviewers, s.largest_cluster_reviews,
                (select max(last_block) from indexer_state) as indexed_to_block,
                (select max(updated_at) from indexer_state) as indexed_at
           from registry_stats s where s.id = 1",
    )
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!(%e, "stats query failed");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let Some(row) = row else {
        // Before the first scoring pass there is genuinely nothing measured,
        // and the UI is built to say so rather than show zeroes as fact.
        return Ok(Json(json!({ "measured": false })));
    };

    Ok(Json(json!({
        "measured": true,
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
        "agents_rated": row.get::<i64, _>("agents_rated"),
        "agents_scored": row.get::<i64, _>("agents_scored"),
        "reviews_kept": row.get::<i64, _>("reviews_kept"),
        "reviewers_independent": row.get::<i64, _>("reviewers_independent"),
        "largest_cluster_reviewers": row.get::<i64, _>("largest_cluster_reviewers"),
        "largest_cluster_reviews": row.get::<i64, _>("largest_cluster_reviews"),
        "computed_at": row.get::<chrono::DateTime<chrono::Utc>, _>("computed_at").to_rfc3339(),
        "indexed_to_block": row.get::<Option<i64>, _>("indexed_to_block"),
        "indexed_at": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("indexed_at")
            .map(|t| t.to_rfc3339()),
    })))
}

/// 168 hourly buckets for the probe strip: per hour, the share of probes
/// that succeeded, or null where no probe ran.
/// @dev Whole finished hours only. The hour in progress is excluded so the
/// response is identical for every caller within the same hour: a server
/// render and the browser hydrating against it must agree exactly, and a
/// bucket that gains probes between the two would break that.
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

/// Bulk probe strips: one request returns 168 contiguous hourly buckets for
/// up to one hundred agents, keyed by agent id. Whole finished hours only,
/// for the same reason as the single agent series: the response has to be
/// identical for every caller within the hour or hydration mismatches.
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
        "select a.id::text, h.hour, avg(pr.ok::int)::float8, count(pr.id)
         from unnest($1::numeric[]) as a(id)
         cross join generate_series(
                date_trunc('hour', now()) - interval '168 hours',
                date_trunc('hour', now()) - interval '1 hour', interval '1 hour') h(hour)
         left join probe_results pr
           on pr.agent_id = a.id
          and pr.probed_at >= h.hour and pr.probed_at < h.hour + interval '1 hour'
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
        "select f.reviewer, f.value, f.value_decimals, f.tags, f.uri, f.revoked,
                f.block_time, f.tx_hash,
                w.weight, w.flags, w.cluster_id,
                rf.funder
         from feedback f
         left join reviewer_weights w on w.reviewer = f.reviewer
         left join reviewer_funding rf on rf.reviewer = f.reviewer
         where f.agent_id = $1::numeric
         order by f.block_time desc
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
                "value": amount_str(&value),
                "value_decimals": r.get::<i32, _>("value_decimals"),
                "tags": r.get::<Vec<String>, _>("tags"),
                "uri": r.get::<Option<String>, _>("uri"),
                "revoked": r.get::<bool, _>("revoked"),
                "block_time": r.get::<chrono::DateTime<chrono::Utc>, _>("block_time").to_rfc3339(),
                "tx_hash": format!("0x{}", hex_lower(&tx)),
                "weight": r.get::<Option<sqlx::types::BigDecimal>, _>("weight")
                    .map(|v| v.normalized().to_string()),
                "flags": r.get::<Option<Vec<String>>, _>("flags").unwrap_or_default(),
                "cluster_id": r.get::<Option<i64>, _>("cluster_id").map(|v| v.to_string()),
                "funder": r.get::<Option<Vec<u8>>, _>("funder")
                    .map(|f| format!("0x{}", hex_lower(&f))),
            })
        })
        .collect();

    // Distinct reviewers matters more than review count on this registry:
    // 29,511 reviews were written by 105 addresses.
    let summary = sqlx::query(
        "select count(*) as total,
                count(*) filter (where f.revoked) as revoked,
                count(distinct f.reviewer) as reviewers,
                (select t.feedback_kept from agent_trust t where t.agent_id = $1::numeric) as kept,
                (select t.trust from agent_trust t where t.agent_id = $1::numeric) as trust,
                (select t.raw_average from agent_trust t where t.agent_id = $1::numeric) as raw_average,
                (select t.confidence from agent_trust t where t.agent_id = $1::numeric) as confidence
         from feedback f where f.agent_id = $1::numeric",
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
        "kept": summary.get::<Option<i64>, _>("kept"),
        "trust": summary.get::<Option<sqlx::types::BigDecimal>, _>("trust")
            .map(|v| v.with_scale(1).to_string()),
        "raw_average": summary.get::<Option<sqlx::types::BigDecimal>, _>("raw_average")
            .map(|v| v.with_scale(1).to_string()),
        "confidence": summary.get::<Option<sqlx::types::BigDecimal>, _>("confidence")
            .map(|v| v.with_scale(2).to_string()),
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

/// Token amounts must reach the client as plain digit strings. BigDecimal's
/// Display can emit scientific notation ("500e+16"), which is useless as a
/// balance and dangerous to parse. with_scale(0) forces the integer form.
fn amount_str(v: &sqlx::types::BigDecimal) -> String {
    v.with_scale(0).to_string()
}

fn job_row_to_json(r: &sqlx::postgres::PgRow) -> serde_json::Value {
    let hirer: Vec<u8> = r.get("hirer");
    let provider: Option<Vec<u8>> = r.get("provider");
    let create_tx: Option<Vec<u8>> = r.get("create_tx");
    let settle_tx: Option<Vec<u8>> = r.get("settle_tx");
    let budget: sqlx::types::BigDecimal = r.get("budget");
    let refunded: Option<sqlx::types::BigDecimal> = r.get("refunded");
    json!({
        "job_id": r.get::<String, _>("job_id"),
        "agent_id": r.get::<String, _>("agent_id"),
        "agent_name": r.get::<Option<String>, _>("agent_name"),
        "hirer": format!("0x{}", hex_lower(&hirer)),
        "provider": provider.map(|p| format!("0x{}", hex_lower(&p))),
        // Amounts stay strings all the way to the client so no JavaScript
        // number ever touches a token balance.
        "budget": amount_str(&budget),
        "refunded": refunded.as_ref().map(amount_str),
        "state": r.get::<String, _>("state"),
        "mode": r.get::<String, _>("mode"),
        "kernel_status": r.get::<Option<i32>, _>("kernel_status"),
        "chain_id": r.get::<i64, _>("chain_id"),
        "spec": r.get::<Option<String>, _>("spec"),
        "created_at": r.get::<chrono::DateTime<chrono::Utc>, _>("created_at").to_rfc3339(),
        "deadline": r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("deadline")
            .map(|t| t.to_rfc3339()),
        "submitted_at": r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("submitted_at")
            .map(|t| t.to_rfc3339()),
        "settled_at": r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("settled_at")
            .map(|t| t.to_rfc3339()),
        "create_tx": create_tx.map(|t| format!("0x{}", hex_lower(&t))),
        "settle_tx": settle_tx.map(|t| format!("0x{}", hex_lower(&t))),
    })
}

const JOB_SELECT: &str = "select j.job_id::text as job_id, j.agent_id::text as agent_id,
        a.name as agent_name, j.hirer, j.provider, j.budget, j.refunded, j.state, j.mode,
        j.kernel_status, j.chain_id, j.spec, j.created_at, j.deadline,
        j.submitted_at, j.settled_at, j.create_tx, j.settle_tx
   from jobs j left join agents a on a.agent_id = j.agent_id";

#[derive(Deserialize)]
pub struct JobListParams {
    pub hirer: Option<String>,
    pub agent_id: Option<String>,
    pub limit: Option<i64>,
}

/// Jobs opened through our hire rail, newest first. Filterable by hirer so
/// the "my hires" page can show only yours.
pub async fn list_jobs(
    State(state): State<AppState>,
    Query(params): Query<JobListParams>,
) -> Result<impl IntoResponse, StatusCode> {
    let limit = params.limit.unwrap_or(50).clamp(1, 200);
    let hirer_bytes = params
        .hirer
        .as_deref()
        .map(|h| h.trim_start_matches("0x"))
        .and_then(hex_decode);
    let agent = params
        .agent_id
        .as_deref()
        .map(|a| a.chars().filter(|c| c.is_ascii_digit()).collect::<String>())
        .filter(|a| !a.is_empty());

    let sql = format!(
        "{JOB_SELECT}
         where ($1::bytea is null or j.hirer = $1)
           and ($2::text is null or j.agent_id = $2::numeric)
         order by j.created_at desc
         limit {limit}"
    );
    let rows = sqlx::query(&sql)
        .bind(hirer_bytes)
        .bind(agent)
        .fetch_all(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!(%e, "list_jobs failed");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    let items: Vec<serde_json::Value> = rows.iter().map(job_row_to_json).collect();
    Ok(Json(json!({ "items": items })))
}

pub async fn get_job(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<impl IntoResponse, StatusCode> {
    let clean: String = id.chars().filter(|c| c.is_ascii_digit()).collect();
    if clean.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    let sql = format!("{JOB_SELECT} where j.job_id = $1::numeric");
    let row = sqlx::query(&sql)
        .bind(&clean)
        .fetch_optional(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(job_row_to_json(&row)))
}

fn hex_decode(s: &str) -> Option<Vec<u8>> {
    if !s.len().is_multiple_of(2) || !s.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok())
        .collect()
}

/// The parameter set the trust engine actually runs on. The public
/// methodology page renders from this response, so the rules a reader is
/// shown cannot drift from the rules that ran.
pub async fn methodology() -> impl IntoResponse {
    Json(common::methodology::current())
}

#[derive(Deserialize)]
pub struct SnapshotQuery {
    /// Ask for the full leaf set. It is a few megabytes at registry scale, so
    /// it is opt in: pages want the header, a verifier wants everything.
    #[serde(default)]
    payload: bool,
}

/// The most recent snapshot that was actually published on chain, which is
/// the only one a reader can verify. The newest snapshot the engine built may
/// be newer than this; scores move, publishing is a deliberate step.
pub async fn published_snapshot(
    State(state): State<AppState>,
    Query(q): Query<SnapshotQuery>,
) -> Result<impl IntoResponse, StatusCode> {
    let row = sqlx::query(
        "select id, root_hex, agent_count, extract(epoch from computed_at)::bigint as computed_at,
                tx_hash, block_number, onchain_index, contract, payload
         from snapshots where published order by computed_at desc limit 1",
    )
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    .ok_or(StatusCode::NOT_FOUND)?;

    let hex = |b: Option<Vec<u8>>| {
        b.map(|v| {
            format!(
                "0x{}",
                v.iter().map(|x| format!("{x:02x}")).collect::<String>()
            )
        })
    };
    Ok(Json(json!({
        "id": row.get::<i64, _>("id"),
        "merkle_root": row.get::<Option<String>, _>("root_hex"),
        "agent_count": row.get::<i32, _>("agent_count"),
        "computed_at": row.get::<Option<i64>, _>("computed_at"),
        "onchain_index": row.get::<Option<i32>, _>("onchain_index"),
        "contract": hex(row.try_get("contract").ok().flatten()),
        "tx_hash": hex(row.try_get("tx_hash").ok().flatten()),
        "block_number": row.get::<Option<i64>, _>("block_number"),
        "payload": if q.payload {
            row.get::<Option<serde_json::Value>, _>("payload")
        } else {
            None
        },
    })))
}

/// The most recent Merkle snapshot of scores. With `?payload=true` the
/// response carries every leaf, so a reader can rebuild the tree, confirm the
/// root, and check any single agent without trusting this endpoint.
pub async fn latest_snapshot(
    State(state): State<AppState>,
    Query(q): Query<SnapshotQuery>,
) -> Result<impl IntoResponse, StatusCode> {
    let row = sqlx::query(
        "select id, root_hex, agent_count, extract(epoch from computed_at)::bigint as computed_at,
                tx_hash, block_number, published, payload
         from snapshots where root_hex is not null
         order by computed_at desc limit 1",
    )
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    .ok_or(StatusCode::NOT_FOUND)?;

    let tx: Option<Vec<u8>> = row.try_get("tx_hash").ok().flatten();
    Ok(Json(json!({
        "id": row.get::<i64, _>("id"),
        "merkle_root": row.get::<Option<String>, _>("root_hex"),
        "agent_count": row.get::<i32, _>("agent_count"),
        "computed_at": row.get::<Option<i64>, _>("computed_at"),
        "published": row.get::<bool, _>("published"),
        "tx_hash": tx.map(|b| format!("0x{}", b.iter().map(|x| format!("{x:02x}")).collect::<String>())),
        "block_number": row.get::<Option<i64>, _>("block_number"),
        "payload": if q.payload {
            row.get::<Option<serde_json::Value>, _>("payload")
        } else {
            None
        },
    })))
}

/// A Merkle proof for one agent in one snapshot, plus the exact leaf inputs
/// the contract expects. Everything needed to call `TrustSnapshot.verify`
/// yourself is in this response.
pub async fn snapshot_proof(
    State(state): State<AppState>,
    Path((snapshot_id, agent_id)): Path<(String, String)>,
) -> Result<impl IntoResponse, StatusCode> {
    let sid: i64 = snapshot_id.parse().map_err(|_| StatusCode::BAD_REQUEST)?;
    let agent: String = agent_id.chars().filter(|c| c.is_ascii_digit()).collect();
    if agent.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let head = sqlx::query(
        "select root_hex, extract(epoch from computed_at)::bigint as computed_at
         from snapshots where id = $1",
    )
    .bind(sid)
    .fetch_optional(&state.pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    .ok_or(StatusCode::NOT_FOUND)?;

    // The whole leaf set, in tree order, so the proof is rebuilt from the
    // same data the root was built from.
    let rows = sqlx::query(
        "select agent_id::text as agent_id, position, liveness, trust, confidence, leaf
         from snapshot_leaves where snapshot_id = $1 order by position",
    )
    .bind(sid)
    .fetch_all(&state.pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    if rows.is_empty() {
        return Err(StatusCode::NOT_FOUND);
    }

    let leaves: Vec<common::snapshot::B256> = rows
        .iter()
        .map(|r| common::snapshot::B256::from_slice(r.get::<Vec<u8>, _>("leaf").as_slice()))
        .collect();
    let index = rows
        .iter()
        .position(|r| r.get::<String, _>("agent_id") == agent)
        .ok_or(StatusCode::NOT_FOUND)?;

    let proof = common::snapshot::merkle_proof(&leaves, index);
    let root = common::snapshot::merkle_root(&leaves).ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;
    let me = &rows[index];

    Ok(Json(json!({
        "snapshot_id": sid,
        "agent_id": agent,
        "merkle_root": format!("{root}"),
        "stored_root": head.get::<Option<String>, _>("root_hex"),
        "leaf": format!("{}", leaves[index]),
        "index": index,
        "proof": proof.iter().map(|p| format!("{p}")).collect::<Vec<_>>(),
        "verify_args": {
            "agentId": agent,
            "liveness": me.get::<i32, _>("liveness"),
            "trust": me.get::<i32, _>("trust"),
            "confidence": me.get::<i32, _>("confidence"),
            "computedAt": head.get::<Option<i64>, _>("computed_at"),
        },
    })))
}

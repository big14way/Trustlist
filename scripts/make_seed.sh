#!/usr/bin/env bash
# Export a bounded sample of real indexed data for CI and cold-start seeding.
# Rows are real chain data from our own indexer, never fabricated. Regenerate
# at each milestone so the seed tracks the schema.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=scripts/ci_seed
mkdir -p "$OUT"

PSQL=(docker compose exec -T db psql -U trustlist -d trustlist -v ON_ERROR_STOP=1)

# 4000 newest agents with fetched cards plus every agent that has feedback,
# so both gate thresholds and the review pipeline have data. card_raw is
# excluded to keep the seed small; endpoints and names are kept.
"${PSQL[@]}" -c "\\copy (
  select agent_id, encode(owner,'hex'), token_uri, card_fetched_at, card_status,
         name, description, categories, endpoints, trust_models,
         registered_block, registered_at, last_seen_block
  from agents
  where agent_id in (
    select agent_id from agents where card_fetched_at is not null
    order by registered_block desc limit 4000
  ) or agent_id in (select distinct agent_id from feedback)
    or agent_id in (select agent_id from probe_results group by agent_id having count(*) >= 24)
) to stdout" | gzip > "$OUT/agents.tsv.gz"

"${PSQL[@]}" -c "\\copy (
  select agent_id, encode(reviewer,'hex'), feedback_index, value, value_decimals,
         tags, endpoint, uri, encode(feedback_hash,'hex'), revoked,
         encode(revoked_tx,'hex'), encode(tx_hash,'hex'), log_index,
         block_number, block_time
  from feedback
  where agent_id in (select agent_id from agents where card_fetched_at is not null
                     or agent_id in (select distinct agent_id from feedback))
  limit 20000
) to stdout" | gzip > "$OUT/feedback.tsv.gz"

"${PSQL[@]}" -c "\\copy (
  select encode(registry,'hex'), last_block, encode(last_block_hash,'hex'), updated_at
  from indexer_state
) to stdout" > "$OUT/indexer_state.tsv"

# Probe history for every agent with 24 or more probes plus the latest score
# rows, so the M2 gate checks and status buckets work against the seed.
"${PSQL[@]}" -c "\\copy (
  select agent_id, endpoint_url, probed_at, ok, http_status, latency_ms,
         failure_kind, encode(body_hash,'hex')
  from probe_results
  where agent_id in (select agent_id from probe_results group by agent_id having count(*) >= 24)
) to stdout" | gzip > "$OUT/probe_results.tsv.gz"

"${PSQL[@]}" -c "\\copy (
  select distinct on (agent_id) agent_id, computed_at, liveness, uptime_7d,
         median_latency, feedback_total, feedback_kept, jobs_completed,
         jobs_disputed, rank_score, status, probes_7d, min_probes
  from agent_scores order by agent_id, computed_at desc
) to stdout" | gzip > "$OUT/agent_scores.tsv.gz"

ls -la "$OUT"
echo "seed written"

#!/usr/bin/env bash
# Load the CI seed into a migrated database. Used by CI and make demo when no
# indexed data exists yet. Idempotent: existing rows win.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DATABASE_URL:?DATABASE_URL must be set}"
SEED=scripts/ci_seed

run_psql() {
  if command -v psql >/dev/null 2>&1; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 "$@"
  else
    docker compose exec -T db psql -U trustlist -d trustlist -v ON_ERROR_STOP=1 "$@"
  fi
}

run_psql -c "
create table if not exists seed_agents (
  agent_id numeric, owner_hex text, token_uri text, card_fetched_at timestamptz,
  card_status text, name text, description text, categories text[],
  endpoints jsonb, trust_models text[], registered_block bigint,
  registered_at timestamptz, last_seen_block bigint
);
truncate seed_agents;"
gunzip -c "$SEED/agents.tsv.gz" | run_psql -c "\\copy seed_agents from pstdin"
run_psql -c "
insert into agents (agent_id, owner, token_uri, card_fetched_at, card_status,
                    name, description, categories, endpoints, trust_models,
                    registered_block, registered_at, last_seen_block)
select agent_id, decode(owner_hex,'hex'), token_uri, card_fetched_at, card_status,
       name, description, coalesce(categories,'{}'), endpoints,
       coalesce(trust_models,'{}'), registered_block, registered_at, last_seen_block
from seed_agents
on conflict (agent_id) do nothing;
drop table seed_agents;"

run_psql -c "
create table if not exists seed_feedback (
  agent_id numeric, reviewer_hex text, feedback_index numeric, value numeric,
  value_decimals int, tags text[], endpoint text, uri text, feedback_hash_hex text,
  revoked boolean, revoked_tx_hex text, tx_hash_hex text, log_index int,
  block_number bigint, block_time timestamptz
);
truncate seed_feedback;"
gunzip -c "$SEED/feedback.tsv.gz" | run_psql -c "\\copy seed_feedback from pstdin"
run_psql -c "
insert into feedback (agent_id, reviewer, feedback_index, value, value_decimals,
                      tags, endpoint, uri, feedback_hash, revoked, revoked_tx,
                      tx_hash, log_index, block_number, block_time)
select agent_id, decode(reviewer_hex,'hex'), feedback_index, value, value_decimals,
       coalesce(tags,'{}'), endpoint, uri, decode(feedback_hash_hex,'hex'), revoked,
       decode(nullif(revoked_tx_hex,''),'hex'), decode(tx_hash_hex,'hex'), log_index,
       block_number, block_time
from seed_feedback
on conflict (tx_hash, log_index) do nothing;
drop table seed_feedback;"

run_psql -c "
create table if not exists seed_state (registry_hex text, last_block bigint, hash_hex text, updated_at timestamptz);
truncate seed_state;"
run_psql -c "\\copy seed_state from pstdin" < "$SEED/indexer_state.tsv"
run_psql -c "
insert into indexer_state (registry, last_block, last_block_hash, updated_at)
select decode(registry_hex,'hex'), last_block, decode(hash_hex,'hex'), updated_at
from seed_state
on conflict (registry) do nothing;
drop table seed_state;"

if [ -f "$SEED/probe_results.tsv.gz" ]; then
  run_psql -c "
  create table if not exists seed_probes (
    agent_id numeric, endpoint_url text, probed_at timestamptz, ok boolean,
    http_status int, latency_ms int, failure_kind text, body_hash_hex text
  );
  truncate seed_probes;"
  gunzip -c "$SEED/probe_results.tsv.gz" | run_psql -c "\\copy seed_probes from pstdin"
  run_psql -c "
  insert into probe_results (agent_id, endpoint_url, probed_at, ok, http_status, latency_ms, failure_kind, body_hash)
  select agent_id, endpoint_url, probed_at, ok, http_status, latency_ms,
         failure_kind, decode(nullif(body_hash_hex,''),'hex')
  from seed_probes p
  where exists (select 1 from agents a where a.agent_id = p.agent_id);
  drop table seed_probes;"
fi

if [ -f "$SEED/agent_scores.tsv.gz" ]; then
  run_psql -c "
  create table if not exists seed_scores (
    agent_id numeric, computed_at timestamptz, liveness numeric, uptime_7d numeric,
    median_latency int, feedback_total int, feedback_kept int, jobs_completed int,
    jobs_disputed int, rank_score numeric, status text, probes_7d int, min_probes int
  );
  truncate seed_scores;"
  gunzip -c "$SEED/agent_scores.tsv.gz" | run_psql -c "\\copy seed_scores from pstdin"
  run_psql -c "
  insert into agent_scores (agent_id, computed_at, liveness, uptime_7d, median_latency,
                            feedback_total, feedback_kept, jobs_completed, jobs_disputed,
                            rank_score, status, probes_7d, min_probes)
  select s.agent_id, s.computed_at, s.liveness, s.uptime_7d, s.median_latency,
         s.feedback_total, s.feedback_kept, s.jobs_completed, s.jobs_disputed,
         s.rank_score, s.status, s.probes_7d, s.min_probes
  from seed_scores s
  where exists (select 1 from agents a where a.agent_id = s.agent_id)
  on conflict (agent_id, computed_at) do nothing;
  drop table seed_scores;"
fi

if [ -f "$SEED/reviewer_weights.tsv.gz" ]; then
  run_psql -c "create table if not exists seed_weights (
    reviewer_hex text, weight numeric, cluster_id bigint, flags text[]);
    truncate seed_weights;"
  gunzip -c "$SEED/reviewer_weights.tsv.gz" | run_psql -c "\\copy seed_weights from pstdin"
  run_psql -c "
  insert into reviewer_weights (reviewer, weight, cluster_id, flags, computed_at)
  select decode(reviewer_hex,'hex'), weight, cluster_id, coalesce(flags,'{}'), now()
  from seed_weights on conflict (reviewer) do nothing;
  drop table seed_weights;"
fi

if [ -f "$SEED/reviewer_funding.tsv.gz" ]; then
  run_psql -c "create table if not exists seed_funding (
    reviewer_hex text, funder_hex text, first_block bigint, outbound_count int);
    truncate seed_funding;"
  gunzip -c "$SEED/reviewer_funding.tsv.gz" | run_psql -c "\\copy seed_funding from pstdin"
  run_psql -c "
  insert into reviewer_funding (reviewer, funder, first_block, outbound_count, traced_at)
  select decode(reviewer_hex,'hex'),
         case when funder_hex is null or funder_hex = '' then null else decode(funder_hex,'hex') end,
         first_block, outbound_count, now()
  from seed_funding on conflict (reviewer) do nothing;
  drop table seed_funding;"
fi

if [ -f "$SEED/agent_trust.tsv.gz" ]; then
  run_psql -c "create table if not exists seed_agent_trust (
    agent_id numeric, trust numeric, confidence numeric, raw_average numeric,
    feedback_total bigint, feedback_kept bigint);
    truncate seed_agent_trust;"
  gunzip -c "$SEED/agent_trust.tsv.gz" | run_psql -c "\\copy seed_agent_trust from pstdin"
  run_psql -c "
  insert into agent_trust (agent_id, trust, confidence, raw_average,
                           feedback_total, feedback_kept, computed_at)
  select agent_id, trust, confidence, raw_average, feedback_total, feedback_kept, now()
  from seed_agent_trust t
  where exists (select 1 from agents a where a.agent_id = t.agent_id)
  on conflict (agent_id) do nothing;
  drop table seed_agent_trust;"
fi

echo "seed loaded"

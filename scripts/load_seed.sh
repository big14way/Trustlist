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

echo "seed loaded"

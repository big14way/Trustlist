#!/usr/bin/env bash
# Copy the local index into the hosted database that serves the public site.
#
# The local database is 6.4 GB and the hosted one is a free tier, so this is
# a deliberate subset rather than a dump. What gets copied is chosen by what
# the site actually reads:
#
#   agents            all of them, because the headline count has to be the
#                     real one and any agent page must resolve
#   agent_scores      the newest row per agent only. The local table keeps
#                     every scoring pass ever run, 22.8 million rows for
#                     81,097 agents, and the site only ever reads the latest
#   probe_results     a recent window, because the probe strip draws 7 days
#                     and nothing on the site looks further back
#   the trust tables  in full, they are small
#
# Nothing is invented and nothing is rounded. This is the same data, with
# history the site never reads left behind.
#
# Usage: scripts/sync_prod_db.sh [--probe-days N] [--yes]
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
load_env_files

PROBE_DAYS=7
ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --probe-days) PROBE_DAYS=$2; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done

: "${PROD_DATABASE_URL:?PROD_DATABASE_URL must be set, see docs/HOSTING.md}"

say() { printf '\n==> %s\n' "$1"; }

# psql and pg_dump come from the compose container so the host needs neither.
lpsql() { docker compose exec -T db psql -U trustlist -d trustlist "$@"; }
rpsql() { docker compose exec -T db psql "$PROD_DATABASE_URL" "$@"; }
pipe()  { docker compose exec -T db sh -c "$1"; }

say "check both ends"
LOCAL_AGENTS=$(lpsql -tAc "select count(*) from agents")
echo "  local agents  $LOCAL_AGENTS"
rpsql -tAc "select 1" >/dev/null || { echo "cannot reach the hosted database" >&2; exit 1; }
REMOTE_BEFORE=$(rpsql -tAc "select count(*) from agents")
echo "  hosted agents $REMOTE_BEFORE (before)"

if [ "$ASSUME_YES" != "1" ]; then
  printf '\nThis replaces the hosted contents with a copy of the local index. Continue? [y/N] '
  read -r a
  case "$a" in y|Y|yes|YES) ;; *) echo "nothing was copied"; exit 1 ;; esac
fi

# Order matters: agents first, everything else references it.
say "agents"
pipe "pg_dump -U trustlist -d trustlist -t agents --data-only --no-owner \
  | psql '$PROD_DATABASE_URL' -v ON_ERROR_STOP=1 -q -c 'truncate agents cascade' -f -" \
  >/dev/null 2>&1 || {
  # A single statement plus a stream cannot share one psql invocation, so do
  # it in two when the combined form is refused.
  rpsql -q -c "truncate agents cascade"
  pipe "pg_dump -U trustlist -d trustlist -t agents --data-only --no-owner | psql '$PROD_DATABASE_URL' -v ON_ERROR_STOP=1 -q"
}
echo "  copied $(rpsql -tAc 'select count(*) from agents')"

say "the newest score per agent"
rpsql -q -c "truncate agent_scores"
pipe "pg_dump -U trustlist -d trustlist --data-only --no-owner \
  --table agent_scores 2>/dev/null | head -0" >/dev/null 2>&1 || true
# A dump cannot express "latest row per agent", so this one goes through a
# copy of a query rather than pg_dump.
lpsql -tAc "copy (
  select distinct on (agent_id) *
  from agent_scores
  order by agent_id, computed_at desc
) to stdout" > /tmp/latest_scores.tsv
wc -l < /tmp/latest_scores.tsv | sed 's/^/  rows: /'
docker compose exec -T db sh -c "psql '$PROD_DATABASE_URL' -v ON_ERROR_STOP=1 -q -c '\\copy agent_scores from stdin'" < /tmp/latest_scores.tsv
rm -f /tmp/latest_scores.tsv
echo "  copied $(rpsql -tAc 'select count(*) from agent_scores')"

say "probe history, last $PROBE_DAYS days"
rpsql -q -c "truncate probe_results"
lpsql -tAc "copy (
  select * from probe_results
  where probed_at > now() - interval '$PROBE_DAYS days'
) to stdout" > /tmp/probes.tsv
wc -l < /tmp/probes.tsv | sed 's/^/  rows: /'
docker compose exec -T db sh -c "psql '$PROD_DATABASE_URL' -v ON_ERROR_STOP=1 -q -c '\\copy probe_results from stdin'" < /tmp/probes.tsv
rm -f /tmp/probes.tsv
echo "  copied $(rpsql -tAc 'select count(*) from probe_results')"

say "trust, snapshots and indexer state"
for t in feedback reviewer_weights reviewer_funding agent_trust snapshots snapshot_leaves indexer_state probe_schedule jobs; do
  if lpsql -tAc "select to_regclass('public.$t')" | grep -q "$t"; then
    rpsql -q -c "truncate $t cascade" 2>/dev/null || true
    pipe "pg_dump -U trustlist -d trustlist -t $t --data-only --no-owner | psql '$PROD_DATABASE_URL' -v ON_ERROR_STOP=1 -q"
    printf '  %-18s %s\n' "$t" "$(rpsql -tAc "select count(*) from $t")"
  fi
done

say "what the hosted site will report"
rpsql -tAc "select 'agents', count(*) from agents
  union all select 'scored', count(*) from agent_scores
  union all select 'probes', count(*) from probe_results
  union all select 'feedback', count(*) from feedback" \
  | while IFS='|' read -r k v; do printf '  %-10s %s\n' "$k" "$v"; done
echo "  size      $(rpsql -tAc "select pg_size_pretty(pg_database_size(current_database()))")"

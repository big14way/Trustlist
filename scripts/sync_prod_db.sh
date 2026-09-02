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
#   probe_results     not copied at all. Every probe figure the site shows is
#                     an aggregate, and the rollups below hold those answers
#                     in a fifth of the space. 7 days of raw rows is about
#                     740 MB and does not fit
#   probe_hourly      the 168 hourly buckets the probe strip draws, so the
#   probe_endpoint_*  hosted site serves the full week rather than a stub
#   the trust tables  in full, they are small
#
# Nothing is invented and nothing is rounded. This is the same data, with
# history the site never reads left behind.
#
# Usage: scripts/sync_prod_db.sh [--yes] [--only table,table]
#
# --only recopies just the named small tables, in foreign key order, and
# leaves agents, scores and rollups alone. It exists for repairing a run
# that stopped partway, which is cheaper than the full twenty minutes.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
load_env_files

ASSUME_YES=0
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) ASSUME_YES=1; shift ;;
    --only) ONLY=$2; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
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

# Will it fit?
#
# This check exists because the answer once was no. A 7 day probe window is
# about 2.0 million rows at roughly 360 bytes on disk, some 740 MB, against a
# 1 GB hosted database already holding 370 MB of everything else. The copy
# truncated first, ran out of disk halfway, and left the site with no probe
# history, a stale registry_stats and a suspended database. Measuring before
# truncating is the difference between a refusal and an outage.
say "will it fit"
# Everything that lands, sized from the local tables it is copied from.
# agent_scores is the exception: only the newest row per agent is sent, so its
# local size (millions of historical passes) is not what arrives.
OTHER_BYTES=$(lpsql -tAc "
  select coalesce(sum(pg_total_relation_size(relid)),0)::bigint
  from pg_stat_user_tables
  where relname not in ('probe_results','agent_scores',
                        '_sqlx_migrations','seed_agents')")
SCORE_ROWS=$(lpsql -tAc "select count(distinct agent_id) from agent_scores")
NEED=$(( OTHER_BYTES + SCORE_ROWS * 180 ))
CAP_BYTES=${PROD_DB_CAPACITY_BYTES:-1073741824}
# Leave headroom: Postgres needs room for WAL, indexes built during COPY, and
# the dead pages a truncate does not return until vacuum.
BUDGET=$(( CAP_BYTES * 75 / 100 ))
printf '  estimated total   %s MB\n' "$(( NEED / 1048576 ))"
printf '  usable budget     %s MB of %s MB\n' "$(( BUDGET / 1048576 ))" "$(( CAP_BYTES / 1048576 ))"
if [ "$NEED" -gt "$BUDGET" ]; then
  cat >&2 <<EOF

This will not fit, so nothing has been touched.

  needs  $(( NEED / 1048576 )) MB
  budget $(( BUDGET / 1048576 )) MB

The largest copied tables are:

$(lpsql -tAc "select '    ' || relname || '  ' || pg_size_pretty(pg_total_relation_size(relid))
  from pg_stat_user_tables
  where relname not in ('probe_results','agent_scores','_sqlx_migrations','seed_agents')
  order by pg_total_relation_size(relid) desc limit 5")

Raise the ceiling with PROD_DB_CAPACITY_BYTES if the plan has more room.
EOF
  exit 1
fi
echo "  fits"

if [ "$ASSUME_YES" != "1" ]; then
  printf '\nThis replaces the hosted contents with a copy of the local index. Continue? [y/N] '
  read -r a
  case "$a" in y|Y|yes|YES) ;; *) echo "nothing was copied"; exit 1 ;; esac
fi

if [ -n "$ONLY" ]; then
  say "only: $ONLY (agents, scores and rollups left as they are)"
else
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

# probe_results is deliberately not copied. The rollups that replace it are
# picked up by the derived table list below, the same mechanism that stopped
# registry_stats being forgotten.
say "probe history"
rpsql -q -c "truncate probe_results"
echo "  raw probes left behind, the rollups carry the same answers"
fi

say "trust, snapshots and indexer state"
# registry_stats is the one the homepage reads for every headline number,
# and leaving it out made the hosted site say "the prober has not completed
# its first scoring pass" while holding 321,519 agents. The list is now
# derived rather than typed, so a new table cannot be forgotten the same way.
#
# Parents before children. Alphabetical order put snapshot_leaves ahead of
# snapshots, so the leaves of a snapshot the hosted side had not received
# yet failed their foreign key and the whole run stopped there, with the
# hosted leaves table already truncated. A table that another table
# references by foreign key is copied first; the rest follow by name.
SMALL_TABLES=$(lpsql -tAc "
  select t.table_name from information_schema.tables t
  where t.table_schema = 'public'
    and t.table_name not in ('agents','agent_scores','probe_results',
                             '_sqlx_migrations','seed_agents')
  order by exists (
      select 1 from pg_constraint c
      where c.contype = 'f'
        and c.confrelid = ('public.' || t.table_name)::regclass
    ) desc, t.table_name")
for t in $SMALL_TABLES; do
  if [ -n "$ONLY" ]; then
    case ",$ONLY," in *",$t,"*) ;; *) continue ;; esac
  fi
  if lpsql -tAc "select to_regclass('public.$t')" | grep -q "$t"; then
    rpsql -q -c "truncate $t cascade" 2>/dev/null || true
    pipe "pg_dump -U trustlist -d trustlist -t $t --data-only --no-owner | psql '$PROD_DATABASE_URL' -v ON_ERROR_STOP=1 -q"
    printf '  %-18s %s\n' "$t" "$(rpsql -tAc "select count(*) from $t")"
  fi
done

say "what the hosted site will report"
rpsql -tAc "select 'agents', count(*) from agents
  union all select 'scored', count(*) from agent_scores
  union all select 'strip hrs', count(*) from probe_hourly
  union all select 'endpoints', count(*) from probe_endpoint_recent
  union all select 'feedback', count(*) from feedback" \
  | while IFS='|' read -r k v; do printf '  %-10s %s\n' "$k" "$v"; done
echo "  size      $(rpsql -tAc "select pg_size_pretty(pg_database_size(current_database()))")"

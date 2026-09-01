#!/usr/bin/env bash
# Bring the hosted database back after a suspension, and wait until it is
# really serving rather than just reporting a state change.
#
# Written because the obvious one liner does not work from an interactive
# shell: RENDER_API_KEY lives in .env, not in the environment, so a bare
# curl sends "Authorization: Bearer " and Render answers Unauthorized. That
# reads exactly like a bad key, which sends you looking in the wrong place.
#
# Usage: bash scripts/resume_db.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
load_env_files

DB_ID="${RENDER_DB_ID:-dpg-daamobm7bikc738vcm4g-a}"
: "${RENDER_API_KEY:?RENDER_API_KEY is not in .env, so there is nothing to authenticate with}"

api() {
  curl -s --max-time 45 -H "Authorization: Bearer $RENDER_API_KEY" "$@"
}

status_now() {
  api "https://api.render.com/v1/postgres/$DB_ID" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null \
    || echo "unreadable"
}

BEFORE=$(status_now)
echo "status before: $BEFORE"
if [ "$BEFORE" = "available" ]; then
  echo "already available, nothing to do"
  exit 0
fi

echo "resuming $DB_ID"
RESP=$(api -X POST -H "Content-Type: application/json" \
  "https://api.render.com/v1/postgres/$DB_ID/resume" -w '\n%{http_code}')
CODE=$(printf '%s' "$RESP" | tail -1)
BODY=$(printf '%s' "$RESP" | sed '$d')
echo "  HTTP $CODE ${BODY:+$BODY}"

if [ "$CODE" = "401" ] || [ "$CODE" = "403" ]; then
  echo "the key was rejected, so check RENDER_API_KEY in .env" >&2
  exit 1
fi

# A resume returns before the instance is serving. Poll the real thing, the
# API's own health endpoint, rather than trusting the state field.
echo "waiting for the API to answer"
for i in $(seq 1 60); do
  s=$(status_now)
  h=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
        https://trustlist-api.onrender.com/v1/health 2>/dev/null || echo 000)
  printf '  %2ds  db=%-12s api=%s\n' "$((i * 10))" "$s" "$h"
  if [ "$h" = "200" ]; then
    echo
    echo "back up. Next: bash scripts/sync_prod_db.sh"
    exit 0
  fi
  sleep 10
done

echo
echo "the database did not start serving within ten minutes." >&2
echo "Check the Render dashboard: a free instance that is over its storage" >&2
echo "limit can refuse to resume until the data shrinks." >&2
exit 1

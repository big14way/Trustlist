#!/usr/bin/env bash
# Point the hosted database's IP allow list at whatever address this machine
# currently has, then prove a connection actually works.
#
# The database only accepts external connections from addresses on its allow
# list. Everything else is refused at the TLS handshake, which surfaces as
#
#   psql: error: ... SSL connection has been closed unexpectedly
#
# That reads like a broken database or a bad password. It is neither: it is a
# home connection that was given a new address by its ISP, so the entry added
# for the last sync no longer matches. The API is unaffected throughout,
# because it connects from inside Render's own network, which is why the site
# can be perfectly healthy while psql cannot get in at all.
#
# The entry is for running scripts/sync_prod_db.sh from a laptop. Remove it
# when the syncing is done: scripts/allow_my_ip.sh --clear
#
# Usage: bash scripts/allow_my_ip.sh [--clear]
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
load_env_files

DB_ID="${RENDER_DB_ID:-dpg-daamobm7bikc738vcm4g-a}"
: "${RENDER_API_KEY:?RENDER_API_KEY is not in .env}"
CLEAR=0
[ "${1:-}" = "--clear" ] && CLEAR=1

api() { curl -s --max-time 45 -H "Authorization: Bearer $RENDER_API_KEY" "$@"; }

echo "current allow list:"
api "https://api.render.com/v1/postgres/$DB_ID" | python3 -c "
import json, sys
for e in json.load(sys.stdin).get('ipAllowList') or []:
    print('  %s  %s' % (e.get('cidrBlock'), e.get('description', '')))
else:
    pass" || echo "  (could not read)"

BODY=$(mktemp "${TMPDIR:-/tmp}/allowlist.XXXXXX.json")
trap 'rm -f "$BODY"' EXIT

if [ "$CLEAR" = "1" ]; then
  printf '{"ipAllowList": []}' > "$BODY"
  echo "clearing the allow list"
else
  IP=$(curl -s --max-time 20 https://ifconfig.me 2>/dev/null \
       || curl -s --max-time 20 https://api.ipify.org 2>/dev/null)
  case "$IP" in
    *[!0-9.]*|"") echo "could not determine this machine's public address" >&2; exit 1 ;;
  esac
  echo "this machine is $IP"
  # Built by json.dumps rather than string interpolation, so the address can
  # never break out of the field it belongs in.
  python3 -c "
import json, sys
print(json.dumps({'ipAllowList': [{
    'cidrBlock': sys.argv[1] + '/32',
    'description': 'sync from the maintainer laptop, remove when done',
}]}))" "$IP" > "$BODY"
fi

CODE=$(api -X PATCH -H "Content-Type: application/json" --data @"$BODY" \
  -o /dev/null -w '%{http_code}' "https://api.render.com/v1/postgres/$DB_ID")
echo "PATCH returned HTTP $CODE"
case "$CODE" in
  2*) ;;
  401|403) echo "the key was rejected, check RENDER_API_KEY in .env" >&2; exit 1 ;;
  *) echo "the allow list was not updated" >&2; exit 1 ;;
esac

[ "$CLEAR" = "1" ] && { echo "cleared"; exit 0; }

# The rule takes a moment to reach the proxy, so prove the connection rather
# than trusting the response code.
echo "checking a real connection"
for i in $(seq 1 20); do
  if docker compose exec -T db psql "$PROD_DATABASE_URL" -tAc "select 1" 2>/dev/null \
     | tr -d ' \n' | grep -q '^1$'; then
    echo "connected after $((i * 10))s"
    echo
    echo "Next: bash scripts/sync_prod_db.sh"
    exit 0
  fi
  printf '  %ds\n' "$((i * 10))"
  sleep 10
done

echo "still refused after three minutes." >&2
echo "If this machine is behind a changing address, check it again with" >&2
echo "  curl -s https://ifconfig.me" >&2
exit 1

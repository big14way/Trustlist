#!/usr/bin/env bash
# One command to a working local stack, per SPEC Section 30.1.
#
# Postgres, migrations, a seed of real indexed data so nobody waits on a
# backfill, then indexer, prober, trust engine, api, and web. Everything the
# UI shows after this comes from the seed, which is real chain data exported
# by scripts/make_seed.sh, never invented rows.
set -euo pipefail
cd "$(dirname "$0")/.."

set -a
# shellcheck disable=SC1091
source .env.example
[ -f .env ] && source .env
set +a

# .env.example documents optional settings as empty placeholders. Exported,
# an empty value silently beats a real one set elsewhere, which is how the
# web app lost its snapshot address and the verify drawer went blank. An
# empty placeholder is not configuration, so drop it.
while read -r name; do
  [ -n "$name" ] || continue
  [ -z "${!name:-}" ] && unset "$name"
done < <(grep -oE '^[A-Z_][A-Z0-9_]*=' .env.example | tr -d '=')

API_PORT="${API_PORT:-8080}"
WEB_PORT="${WEB_PORT:-3000}"

say() { printf "\n==> %s\n" "$1"; }

say "postgres"
docker compose up -d db
docker compose exec -T db sh -c 'until pg_isready -U trustlist -d trustlist; do sleep 1; done'

say "building (this is the slow step on a cold machine)"
cargo build --release --workspace

if [ ! -d web/node_modules ]; then
  say "installing web dependencies"
  (cd web && npm ci --no-audit --no-fund)
fi

# The api runs the migrations on startup, so it goes first and everything
# else waits for it.
say "api on :$API_PORT"
pkill -f "target/release/api" 2>/dev/null || true
nohup ./target/release/api > /tmp/api.log 2>&1 &

for _ in $(seq 1 60); do
  curl -sf "http://localhost:$API_PORT/v1/health" >/dev/null && break
  sleep 1
done
if ! curl -sf "http://localhost:$API_PORT/v1/health" >/dev/null; then
  echo "api did not come up, see /tmp/api.log" >&2
  tail -20 /tmp/api.log >&2
  exit 1
fi

# Seed only an empty database. A machine that has already indexed keeps its
# own data, which is always better than the sample.
COUNT=$(docker compose exec -T db psql -U trustlist -d trustlist -tAc \
  "select count(*) from agents" 2>/dev/null || echo 0)
if [ "${COUNT:-0}" -eq 0 ]; then
  say "loading the seed (real indexed rows, so the UI has something true to show)"
  bash scripts/load_seed.sh
else
  say "database already has $COUNT agents, keeping them"
fi

say "indexer, prober, trust engine"
bash scripts/run_services.sh indexer prober trust

say "web on :$WEB_PORT"
pkill -f "next dev" 2>/dev/null || true
(cd web && nohup npm run dev > /tmp/web.log 2>&1 &)

for _ in $(seq 1 90); do
  curl -sf "http://localhost:$WEB_PORT/" >/dev/null && break
  sleep 1
done

AGENTS=$(curl -sf "http://localhost:$API_PORT/v1/stats" 2>/dev/null \
  | python3 -c "import json,sys;print(json.load(sys.stdin).get('registered','?'))" 2>/dev/null || echo "?")

say "up"
echo "  web     http://localhost:$WEB_PORT"
echo "  api     http://localhost:$API_PORT/v1/health"
echo "  agents  $AGENTS indexed"
echo "  logs    /tmp/{api,indexer,prober,trust,web}.log"

# Best effort, and never a reason to fail the run.
if command -v open >/dev/null 2>&1; then
  open "http://localhost:$WEB_PORT" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "http://localhost:$WEB_PORT" 2>/dev/null || true
fi

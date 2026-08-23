#!/usr/bin/env bash
# Start the local service stack detached, so it outlives the shell that
# launched it. Logs land in /tmp/<service>.log.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# shellcheck disable=SC1091
source .env.example
[ -f .env ] && source .env
set +a
for svc in "$@"; do
  pkill -f "target/release/$svc" 2>/dev/null || true
done
sleep 1
for svc in "$@"; do
  nohup ./target/release/"$svc" > "/tmp/$svc.log" 2>&1 &
  disown || true
done
echo "started: $*"

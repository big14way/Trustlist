#!/usr/bin/env bash
# Record that a snapshot was published on chain. Publishing is a deliberate
# step run by a person, so the database learns about it here rather than
# guessing. Without this the app would have no way to tell which of the
# snapshots it built is the one a reader can actually verify.
#
# Usage: scripts/record_publish.sh <snapshot_id> <onchain_index> <tx_hash> <block> <contract>
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -eq 5 ] || { echo "usage: $0 <snapshot_id> <onchain_index> <tx_hash> <block> <contract>" >&2; exit 1; }
SNAP_ID=$1; IDX=$2; TX=${3#0x}; BLOCK=$4; CONTRACT=${5#0x}

run_sql() {
  if command -v psql >/dev/null 2>&1; then
    psql "$DATABASE_URL" -tAc "$1"
  else
    docker compose exec -T db psql -U trustlist -d trustlist -tAc "$1"
  fi
}

run_sql "update snapshots set published = true, onchain_index = $IDX,
         tx_hash = decode('$TX','hex'), block_number = $BLOCK,
         contract = decode('$CONTRACT','hex')
         where id = $SNAP_ID"
echo "snapshot $SNAP_ID recorded as on chain entry $IDX in 0x$CONTRACT"

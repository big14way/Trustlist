#!/usr/bin/env bash
# Build a snapshot and publish it on a local chain, so the M6 gate has
# something real to check.
#
# Until this existed the snapshot half of the gate only ever ran on one
# laptop: CI loaded the seed, never built a snapshot, and both snapshot
# endpoints returned 404, so the check that the root we serve matches the
# root on chain had never once run on a push. This does the real thing
# instead of relaxing the check: start a chain, run the trust engine once
# over the seeded scores, deploy TrustSnapshot, publish the root, and record
# the publish in the database exactly the way a mainnet publish is recorded.
#
# The chain is anvil, not BSC, and that is the honest limit of this: it
# proves our own pipeline agrees with a deployed TrustSnapshot, not that
# anything is published on mainnet. Mainnet publishing stays a deliberate,
# human step with a funded key.
#
# Needs a migrated and seeded database and forge, cast and anvil on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
load_env_files

: "${DATABASE_URL:?DATABASE_URL must be set}"

PORT="${DEVCHAIN_PORT:-8545}"
RPC="http://127.0.0.1:$PORT"
# anvil's first well known development account. Public by design, and it only
# ever signs on a throwaway local chain.
DEV_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

say() { printf '\n==> %s\n' "$1"; }

run_sql() {
  if command -v psql >/dev/null 2>&1; then
    psql "$DATABASE_URL" -tAc "$1"
  else
    docker compose exec -T db psql -U trustlist -d trustlist -tAc "$1"
  fi
}

say "chain on $RPC"
if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
  echo "  reusing the node already listening on $PORT"
else
  nohup anvil --port "$PORT" --chain-id 31337 --silent > /tmp/anvil.log 2>&1 &
  for _ in $(seq 1 30); do
    cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break
    sleep 1
  done
  cast block-number --rpc-url "$RPC" >/dev/null 2>&1 || {
    echo "anvil did not come up, see /tmp/anvil.log" >&2
    tail -20 /tmp/anvil.log >&2
    exit 1
  }
  echo "  started anvil"
fi
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")

say "trust engine, one pass over the seeded scores"
cargo run --release -p trust -- --once

SNAP=$(run_sql "select id, root_hex, agent_count, extract(epoch from computed_at)::bigint
                from snapshots where root_hex is not null order by id desc limit 1")
[ -n "$SNAP" ] || {
  echo "the trust engine built no snapshot, so there is nothing to publish." >&2
  echo "that means no agent in agent_scores has status live, flaky or down." >&2
  exit 1
}
IFS='|' read -r SNAP_ID ROOT COUNT COMPUTED_AT <<< "$SNAP"
echo "  snapshot $SNAP_ID, root $ROOT, $COUNT agents"

say "deploy TrustSnapshot and publish the root"
# An empty TRUST_SNAPSHOT is not an address, and forge's envOr would choke on
# it, so unset it and let the script deploy a fresh register.
[ -n "${TRUST_SNAPSHOT:-}" ] || unset TRUST_SNAPSHOT
OUT=$(cd contracts && DEPLOYER_KEY="$DEV_KEY" \
  SNAPSHOT_ROOT="$ROOT" SNAPSHOT_AGENT_COUNT="$COUNT" SNAPSHOT_COMPUTED_AT="$COMPUTED_AT" \
  forge script script/PublishSnapshot.s.sol:PublishSnapshot \
  --rpc-url "$RPC" --broadcast 2>&1) || {
  echo "$OUT" | tail -30 >&2
  exit 1
}

# Read the address and the receipt back out of the broadcast record rather
# than out of the console output. The publish call is the last transaction
# the script sent, and whatever it was sent to is the register, whether this
# run deployed it or reused one.
BROADCAST="contracts/broadcast/PublishSnapshot.s.sol/$CHAIN_ID/run-latest.json"
read -r ADDR TX BLOCK < <(python3 - "$BROADCAST" <<'PY'
import json, sys
run = json.load(open(sys.argv[1]))
tx = run["transactions"][-1]
if not (tx.get("function") or "").startswith("publish("):
    sys.exit(f"last broadcast transaction is {tx.get('function')!r}, not the publish call")
receipt = run["receipts"][-1]
if receipt["transactionHash"] != tx["hash"]:
    sys.exit("the last receipt does not belong to the last transaction")
if int(receipt["status"], 16) != 1:
    sys.exit("the publish transaction reverted")
print(tx["transaction"]["to"], receipt["transactionHash"], int(receipt["blockNumber"], 16))
PY
)

# The index inside the contract's own array, read back from the contract
# rather than assumed, because the register may already hold snapshots.
IDX=$(cast call "$ADDR" 'snapshotCount()(uint256)' --rpc-url "$RPC" | awk '{print $1}')
IDX=$((IDX - 1))

say "record the publish"
bash scripts/record_publish.sh "$SNAP_ID" "$IDX" "$TX" "$BLOCK" "$ADDR"

# The gate reads these to call the contract. Hand them to later workflow
# steps as well as to the caller's shell.
#
# NEXT_PUBLIC_TRUST_SNAPSHOT is deliberately left alone. The browser drawer
# reads it together with NEXT_PUBLIC_CHAIN_ID, which defaults to BSC mainnet,
# so handing the web app an anvil address would point a reader's wallet at
# the wrong chain and show a verification that cannot be true.
export TRUST_SNAPSHOT="$ADDR"
export HIRE_RAIL_RPC="$RPC"
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "TRUST_SNAPSHOT=$ADDR"
    echo "HIRE_RAIL_RPC=$RPC"
  } >> "$GITHUB_ENV"
fi

say "published"
echo "  TrustSnapshot   $ADDR on chain $CHAIN_ID"
echo "  snapshot        db id $SNAP_ID, on chain index $IDX"
echo "  root            $ROOT"
echo "  agents          $COUNT"

#!/usr/bin/env bash
# Publish a trust snapshot root on a real chain.
#
# scripts/ci_snapshot.sh does this for a dev chain: it starts anvil, deploys
# a fresh register every time, and publishes into it. That behaviour is right
# for CI and dangerous on mainnet, where deploying a fresh register on the
# second run would leave two of them and make every proof anyone had already
# checked point at the wrong contract.
#
# So this script refuses to deploy unless asked in as many words. The normal
# path publishes into the register named by TRUST_SNAPSHOT, and the first run
# ever is the only one that passes --deploy-register.
#
# Publishing is deliberate. The trust engine builds a root every cycle and a
# person decides which one goes on chain, which is why this is a script a
# human runs rather than a service that publishes on a timer.
#
# Usage:
#   scripts/publish_snapshot.sh [options]
#
# Options:
#   --deploy-register  deploy a new TrustSnapshot first. First run only.
#   --snapshot ID      publish this snapshot rather than the newest
#   --rpc URL          chain to publish on (default BSC_RPC_HTTP)
#   --yes              skip the confirmation prompt
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
load_env_files

DEPLOY_REGISTER=0
SNAP_ID=""
RPC=""
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --deploy-register) DEPLOY_REGISTER=1; shift ;;
    --snapshot) SNAP_ID=$2; shift 2 ;;
    --rpc) RPC=$2; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done

RPC="${RPC:-${BSC_RPC_HTTP:-}}"
[ -n "$RPC" ] || { echo "no rpc: pass --rpc or set BSC_RPC_HTTP" >&2; exit 1; }
: "${DATABASE_URL:?DATABASE_URL must be set}"
: "${DEPLOYER_KEY:?DEPLOYER_KEY must be set}"

say()  { printf '\n==> %s\n' "$1"; }
fail() { echo "$*" >&2; exit 1; }

run_sql() {
  if command -v psql >/dev/null 2>&1; then
    psql "$DATABASE_URL" -tAc "$1"
  else
    docker compose exec -T db psql -U trustlist -d trustlist -tAc "$1"
  fi
}

SIGNER=$(cast wallet address --private-key "$DEPLOYER_KEY")
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")

# A fork of mainnet answers 56 as well, so the chain id alone cannot tell a
# rehearsal from the real thing.
is_real_mainnet() {
  [ "$CHAIN_ID" = "56" ] || return 1
  case "$RPC" in
    *127.0.0.1*|*localhost*|*0.0.0.0*|*"[::1]"*) return 1 ;;
  esac
  return 0
}

say "the register"
if [ "$DEPLOY_REGISTER" = "1" ]; then
  if [ -n "${TRUST_SNAPSHOT:-}" ]; then
    fail "TRUST_SNAPSHOT is already set to $TRUST_SNAPSHOT.
Deploying a second register would orphan every proof published against the
first one. Drop --deploy-register to publish into the existing register, or
clear TRUST_SNAPSHOT if you really mean to start again."
  fi
  echo "  none yet, this run deploys one"
else
  [ -n "${TRUST_SNAPSHOT:-}" ] || fail "TRUST_SNAPSHOT is not set.
If a register is already deployed, put its address in .env. If this is the
first publish ever, pass --deploy-register."
  CODE=$(cast code "$TRUST_SNAPSHOT" --rpc-url "$RPC")
  [ "$CODE" != "0x" ] || fail "no contract at $TRUST_SNAPSHOT on chain $CHAIN_ID"
  OWNER=$(cast call "$TRUST_SNAPSHOT" 'owner()(address)' --rpc-url "$RPC")
  echo "  $TRUST_SNAPSHOT, owned by $OWNER"
  ALLOWED=$(cast call "$TRUST_SNAPSHOT" 'publishers(address)(bool)' "$SIGNER" --rpc-url "$RPC")
  [ "$ALLOWED" = "true" ] || fail "$SIGNER is not a publisher on that register, so the publish would revert"
fi

say "the snapshot"
if [ -n "$SNAP_ID" ]; then
  case "$SNAP_ID" in *[!0-9]*) fail "snapshot id must be a number" ;; esac
  ROW=$(run_sql "select id, root_hex, agent_count, extract(epoch from computed_at)::bigint, published
                 from snapshots where id = $SNAP_ID and root_hex is not null")
  [ -n "$ROW" ] || fail "snapshot $SNAP_ID does not exist, or has no root"
else
  ROW=$(run_sql "select id, root_hex, agent_count, extract(epoch from computed_at)::bigint, published
                 from snapshots where root_hex is not null order by id desc limit 1")
  [ -n "$ROW" ] || fail "the trust engine has built no snapshot yet, so there is nothing to publish"
fi
IFS='|' read -r SNAP_ID ROOT COUNT COMPUTED_AT PUBLISHED <<< "$ROW"

if [ "$PUBLISHED" = "t" ]; then
  fail "snapshot $SNAP_ID is already recorded as published.
Publishing it again would cost gas and add a duplicate entry. Run the trust
engine for a fresh root, or pass --snapshot with one that is not published."
fi

echo "  snapshot  $SNAP_ID"
echo "  root      $ROOT"
echo "  agents    $COUNT"
echo "  computed  $(date -u -r "$COMPUTED_AT" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || echo "$COMPUTED_AT")"

say "what this will cost"
BALANCE=$(cast balance "$SIGNER" --rpc-url "$RPC")
GAS_PRICE=$(cast gas-price --rpc-url "$RPC")
# A deploy plus a publish, or just a publish. Measured on a mainnet fork, see
# docs/VERIFICATION.md section 17.
GAS_GUESS=$([ "$DEPLOY_REGISTER" = "1" ] && echo 1402741 || echo 224788)
echo "  chain     $CHAIN_ID"
echo "  signer    $SIGNER"
echo "  balance   $(cast to-unit "$BALANCE" ether) BNB"
echo "  gas       about $GAS_GUESS at $(cast to-unit "$GAS_PRICE" gwei) gwei"
echo "  cost      about $(cast to-unit $((GAS_GUESS * GAS_PRICE)) ether) BNB"

if [ "$ASSUME_YES" != "1" ]; then
  if [ "$DEPLOY_REGISTER" = "1" ]; then
    printf '\nThis deploys a NEW register and publishes into it. Do this once. Continue? [y/N] '
  else
    printf '\nPublish this root? [y/N] '
  fi
  read -r answer
  case "$answer" in y|Y|yes|YES) ;; *) echo "nothing was sent"; exit 1 ;; esac
fi

say "publish"
# An empty TRUST_SNAPSHOT is not an address and forge's envOr would choke on
# it, so unset rather than pass an empty string.
[ -n "${TRUST_SNAPSHOT:-}" ] || unset TRUST_SNAPSHOT
OUT=$(cd contracts && DEPLOYER_KEY="$DEPLOYER_KEY" \
  SNAPSHOT_ROOT="$ROOT" SNAPSHOT_AGENT_COUNT="$COUNT" SNAPSHOT_COMPUTED_AT="$COMPUTED_AT" \
  forge script script/PublishSnapshot.s.sol:PublishSnapshot \
  --rpc-url "$RPC" --broadcast 2>&1) || { echo "$OUT" | tail -30 >&2; fail "the publish reverted"; }

BROADCAST="contracts/broadcast/PublishSnapshot.s.sol/$CHAIN_ID/run-latest.json"
# Match receipts to transactions by hash, never by position. Forge writes
# receipts in the order they arrive, which is not the order the transactions
# were sent: a real publish here recorded the deploy's receipt against the
# publish call and the check below caught it. Positions in that file are not
# a reliable way to identify anything, so the only things trusted from it are
# the hashes, and each is resolved against the chain.
read -r ADDR TX BLOCK GAS_USED < <(python3 - "$BROADCAST" <<'PY'
import json, sys
run = json.load(open(sys.argv[1]))
receipts = {r["transactionHash"]: r for r in run["receipts"]}

published = [t for t in run["transactions"]
             if (t.get("function") or "").startswith("publish(")]
if len(published) != 1:
    sys.exit(f"expected exactly one publish call in the broadcast, found {len(published)}")
tx = published[0]

receipt = receipts.get(tx["hash"])
if receipt is None:
    sys.exit(f"no receipt was recorded for the publish call {tx['hash']}")
if int(receipt["status"], 16) != 1:
    sys.exit("the publish transaction reverted")

# Every transaction in the run has to have succeeded, or the register may
# exist without the root in it.
for t in run["transactions"]:
    r = receipts.get(t["hash"])
    if r is None or int(r["status"], 16) != 1:
        sys.exit(f"transaction {t['hash']} has no successful receipt")

print(tx["transaction"]["to"], receipt["transactionHash"],
      int(receipt["blockNumber"], 16), int(receipt["gasUsed"], 16))
PY
)
# The broadcast file records what was sent. What is actually on chain is the
# only thing worth acting on, so the address is confirmed before it is used.
[ "$(cast code "$ADDR" --rpc-url "$RPC")" != "0x" ] \
  || fail "the broadcast names $ADDR as the register but there is no code there"

# The index inside the contract's own array, read back rather than assumed.
IDX=$(cast call "$ADDR" 'snapshotCount()(uint256)' --rpc-url "$RPC" | awk '{print $1}')
IDX=$((IDX - 1))

say "record it"
bash scripts/record_publish.sh "$SNAP_ID" "$IDX" "$TX" "$BLOCK" "$ADDR"

say "published"
echo "  register  $ADDR"
echo "  snapshot  db id $SNAP_ID, on chain index $IDX"
echo "  root      $ROOT"
echo "  agents    $COUNT"
echo "  tx        $TX"
if is_real_mainnet; then
  echo "  bscscan   https://bscscan.com/tx/$TX"
  bash scripts/log_tx.sh "publish snapshot $SNAP_ID root" "$TX" "$BLOCK" "$GAS_USED"
  echo
  echo "Put this in .env and in docs/ADDRESSES.md before the next run:"
  echo "  TRUST_SNAPSHOT=$ADDR"
  echo "  NEXT_PUBLIC_TRUST_SNAPSHOT=$ADDR"
  echo
  echo "The web app reads NEXT_PUBLIC_TRUST_SNAPSHOT with NEXT_PUBLIC_CHAIN_ID,"
  echo "so set both together or the verify drawer points a reader's wallet at"
  echo "the wrong chain."
fi

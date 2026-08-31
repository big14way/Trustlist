#!/usr/bin/env bash
# Hire each of our three agents on mainnet, once, so the advantage report has
# a real job id per task.
#
# TermiX asks for three real tasks. "Real" here means the task was paid for
# through the same ERC-8183 escrow any visitor uses: approve the exact
# budget, hire, the agent submits its deliverable, the hirer accepts and the
# escrow releases. Nothing is simulated and nothing is a dry run.
#
# The budget returns to us because we own the agents we are hiring, which is
# stated in the report rather than hidden. It is why one small purchase of U
# covers every task.
#
# Usage: scripts/hire_for_report.sh [--budget-u 0.05] [--yes]
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
# shellcheck disable=SC1091
source scripts/chainlib.sh
load_env_files

BUDGET_U="0.05"
ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --budget-u) BUDGET_U=$2; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done

RPC="${BSC_RPC_HTTP:?}"
RAIL="${HIRE_RAIL:?}"
TOKEN="${PAYMENT_TOKEN:-0xcE24439F2D9C6a2289F741120FE202248B666666}"
KEY="${DEPLOYER_KEY:?}"
ME=$(cast wallet address --private-key "$KEY")
KERNEL=$(cast call "$RAIL" 'kernel()(address)' --rpc-url "$RPC")
BUDGET=$(cast to-wei "$BUDGET_U" ether)

say() { printf '\n==> %s\n' "$1"; }

# task id | agent id | spec
TASKS="1|322154|Screen USDT, U, WBNB and CAKE for the powers their owner keeps, and cite the chain evidence for each finding.
2|320964|Rank the USDT pools on PancakeSwap V3 by what a 10,000 dollar position would have earned over the last seven days after its own dilution.
3|320966|Report whether PancakeSwap V3 position 7284200 is still in range and whether anything should be done about it."

say "before"
echo "  hirer   $ME"
echo "  rail    $RAIL"
echo "  budget  $BUDGET_U U per task, returned on accept"
echo "  BNB     $(cast to-unit "$(cast balance "$ME" --rpc-url "$RPC")" ether)"
echo "  U       $(cast to-unit "$(cast call "$TOKEN" 'balanceOf(address)(uint256)' "$ME" --rpc-url "$RPC" | awk '{print $1}')" ether)"

if [ "$ASSUME_YES" != "1" ]; then
  printf '\nHire three agents on mainnet? [y/N] '
  read -r a
  case "$a" in y|Y|yes|YES) ;; *) echo "nothing was sent"; exit 1 ;; esac
fi

OUT=docs/report_jobs.tsv
: > "$OUT"

while IFS='|' read -r TASK AGENT SPEC; do
  [ -n "$TASK" ] || continue
  say "task $TASK, agent $AGENT"

  set +e
  send_and_wait "$RPC" "$KEY" "$TOKEN" 'approve(address,uint256)' "$RAIL" "$BUDGET"
  rc=$?; set -e
  [ "$rc" = "0" ] || { echo "approve failed for task $TASK" >&2; exit 1; }

  DEADLINE=$(( $(cast block latest --field timestamp --rpc-url "$RPC") + 86400 ))
  set +e
  send_and_wait "$RPC" "$KEY" "$RAIL" \
    'hire(uint256,address,uint256,uint64,bytes32,string,uint8)' \
    "$AGENT" "$ME" "$BUDGET" "$DEADLINE" "$(cast keccak "$SPEC")" "$SPEC" 0
  rc=$?; set -e
  [ "$rc" = "0" ] || { echo "hire failed for task $TASK" >&2; exit 1; }
  HIRE_TX=$TX_HASH; HIRE_BLOCK=$TX_BLOCK; HIRE_GAS=$TX_GAS_USED

  JOB=$(cast receipt "$HIRE_TX" --rpc-url "$RPC" --json | python3 -c "
import json, sys
r = json.load(sys.stdin)
rail = '$RAIL'.lower()
ours = [l for l in r['logs'] if l['address'].lower() == rail]
if len(ours) != 1:
    sys.exit('expected one HireRail event, found %d' % len(ours))
print(int(ours[0]['topics'][1], 16))")
  echo "  job $JOB"

  PROVIDER_KEY="$KEY" bash scripts/agent_deliver.sh "$JOB" \
    "Delivered for advantage report task $TASK" --rpc "$RPC" --kernel "$KERNEL" --yes >/dev/null
  SUBMIT_TX=$(tail -1 scripts/tx_log.md | grep -oE 'tx/0x[0-9a-f]{64}' | cut -d/ -f2)

  set +e
  send_and_wait "$RPC" "$KEY" "$RAIL" 'accept(uint256)' "$JOB"
  rc=$?; set -e
  [ "$rc" = "0" ] || { echo "accept failed for job $JOB" >&2; exit 1; }
  ACCEPT_TX=$TX_HASH

  bash scripts/log_tx.sh "hire agent $AGENT for report task $TASK, job $JOB" \
    "$HIRE_TX" "$HIRE_BLOCK" "$HIRE_GAS"
  bash scripts/log_tx.sh "accept job $JOB, escrow released" "$ACCEPT_TX" "$TX_BLOCK" "$TX_GAS_USED"

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$TASK" "$AGENT" "$JOB" "$HIRE_TX" "$SUBMIT_TX" "$ACCEPT_TX" >> "$OUT"
  echo "  done, recorded in $OUT"
done <<< "$TASKS"

say "after"
echo "  BNB $(cast to-unit "$(cast balance "$ME" --rpc-url "$RPC")" ether)"
echo "  U   $(cast to-unit "$(cast call "$TOKEN" 'balanceOf(address)(uint256)' "$ME" --rpc-url "$RPC" | awk '{print $1}')" ether)"
column -t "$OUT" 2>/dev/null || cat "$OUT"

#!/usr/bin/env bash
# Deliver a job as the provider: one submit call to the ERC-8183 kernel,
# signed by the address the job names as provider.
#
# Why this exists: the hirer cannot accept a job that was never submitted,
# and nothing in the web app can submit, because submitting is the agent's
# side of the deal. On a dev chain the e2e suite gets around that with
# anvil_impersonateAccount. Mainnet has no such thing, so the provider has to
# sign for real, and this is the only place that happens.
#
# The deliverable is a hash of whatever the agent produced. It is recorded on
# chain so the hirer can check that what they accepted is what they were
# shown.
#
# Usage:
#   scripts/agent_deliver.sh <job_id> [deliverable_text] [options]
#
# Options:
#   --rpc URL     chain the job lives on (default HIRE_RAIL_RPC, then BSC_RPC_HTTP)
#   --kernel ADDR the ERC-8183 kernel holding the job (default HIRE_RAIL_KERNEL)
#   --key NAME    env var holding the provider key (default PROVIDER_KEY)
#   --yes         skip the confirmation prompt
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
# shellcheck disable=SC1091
source scripts/chainlib.sh
load_env_files

JOB_ID=""
DELIVERABLE_TEXT="delivered"
RPC=""
KEY_VAR="PROVIDER_KEY"
KERNEL=""
ASSUME_YES=0
POSITIONAL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --rpc) RPC=$2; shift 2 ;;
    --kernel) KERNEL=$2; shift 2 ;;
    --key) KEY_VAR=$2; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 1 ;;
    *) POSITIONAL=$((POSITIONAL + 1))
       case "$POSITIONAL" in
         1) JOB_ID=$1 ;;
         2) DELIVERABLE_TEXT=$1 ;;
         *) echo "too many arguments" >&2; exit 1 ;;
       esac
       shift ;;
  esac
done

[ -n "$JOB_ID" ] || { sed -n '15,21p' "$0"; exit 1; }
case "$JOB_ID" in *[!0-9]*) echo "job id must be a number" >&2; exit 1 ;; esac

RPC="${RPC:-${HIRE_RAIL_RPC:-${BSC_RPC_HTTP:-}}}"
[ -n "$RPC" ] || { echo "no rpc: pass --rpc or set HIRE_RAIL_RPC" >&2; exit 1; }

KERNEL="${KERNEL:-${HIRE_RAIL_KERNEL:-${AGENTIC_COMMERCE:-}}}"
[ -n "$KERNEL" ] || { echo "no kernel: pass --kernel, or set HIRE_RAIL_KERNEL" >&2; exit 1; }

KEY="${!KEY_VAR:-}"
[ -n "$KEY" ] || {
  echo "$KEY_VAR is empty. The provider is whichever address owns the agent," >&2
  echo "so set $KEY_VAR to that account's key, or pass --key with another name." >&2
  exit 1
}

say() { printf '\n==> %s\n' "$1"; }

# date -u -r <seconds> is BSD only. On GNU coreutils -r means a reference
# file, so the same line prints a bare timestamp on Linux and a readable one
# on a laptop. python3 is already a dependency here, so it does the job the
# same way on both.
utc_time() {
  python3 -c 'import datetime,sys;print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"))' "$1" 2>/dev/null || echo "$1"
}

# A fork of mainnet answers 56 to eth_chainId, exactly as mainnet does, so
# the chain id alone cannot tell a rehearsal from the real thing. Anything
# served from this machine is a fork: real BSC is not on localhost. Getting
# this wrong would put invented hashes in the mainnet transaction log.
is_real_mainnet() {
  [ "$CHAIN_ID" = "56" ] || return 1
  case "$RPC" in
    *127.0.0.1*|*localhost*|*0.0.0.0*|*"[::1]"*) return 1 ;;
  esac
  return 0
}

SIGNER=$(cast wallet address --private-key "$KEY")
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")

if [ "$(cast code "$KERNEL" --rpc-url "$RPC")" = "0x" ]; then
  echo "there is no contract at $KERNEL on this chain." >&2
  echo "HIRE_RAIL_KERNEL may still point at a dev chain. Pass --kernel with" >&2
  echo "the kernel the rail wraps: cast call \$HIRE_RAIL 'kernel()(address)'" >&2
  exit 1
fi

say "read job $JOB_ID from the kernel"
JOB=$(cast call "$KERNEL" \
  'getJob(uint256)((uint256,address,address,address,string,uint256,uint256,uint8,address,uint256,bytes32))' \
  "$JOB_ID" --rpc-url "$RPC")

read -r JOB_PROVIDER JOB_BUDGET JOB_STATUS JOB_DEADLINE < <(python3 - "$JOB" <<'PY'
import re, sys
raw = sys.argv[1].strip()
# cast prints the tuple as ( a, b, "desc", ... ). The description is free
# text and may hold commas, so split on the quotes rather than on commas.
head, _, rest = raw.lstrip("(").partition('"')
desc, _, tail = rest.rpartition('"')
before = [f.strip() for f in head.split(",") if f.strip()]
after = [f.strip() for f in tail.rstrip(")").split(",") if f.strip()]
fields = before + [desc] + after
if len(fields) != 11:
    sys.exit(f"expected 11 job fields, parsed {len(fields)}: {fields}")
num = lambda s: int(re.split(r"\s", s)[0])
print(fields[2], num(fields[5]), num(fields[7]), num(fields[6]))
PY
)

case "$JOB_STATUS" in
  0) STATUS_NAME="Open" ;;
  1) STATUS_NAME="Funded" ;;
  2) STATUS_NAME="Submitted" ;;
  3) STATUS_NAME="Completed" ;;
  4) STATUS_NAME="Rejected" ;;
  5) STATUS_NAME="Expired" ;;
  *) STATUS_NAME="unknown ($JOB_STATUS)" ;;
esac

echo "  provider  $JOB_PROVIDER"
echo "  budget    $(cast to-unit "$JOB_BUDGET" ether)"
echo "  status    $STATUS_NAME"
echo "  deadline  $(utc_time "$JOB_DEADLINE")"

# Both of these would revert on chain. Saying so here costs nothing and
# saves the gas of finding out.
if [ "$(printf '%s' "$JOB_PROVIDER" | tr 'A-Z' 'a-z')" != "$(printf '%s' "$SIGNER" | tr 'A-Z' 'a-z')" ]; then
  echo >&2
  echo "$SIGNER is not this job's provider, so the kernel would reject the submit." >&2
  echo "Sign with the key for $JOB_PROVIDER instead." >&2
  exit 1
fi
if [ "$JOB_STATUS" != "1" ]; then
  echo >&2
  echo "only a Funded job can be submitted, and this one is $STATUS_NAME." >&2
  exit 1
fi
NOW=$(cast block latest --field timestamp --rpc-url "$RPC")
if [ "$NOW" -ge "$JOB_DEADLINE" ]; then
  echo >&2
  echo "the deadline has passed, so this job can only be reclaimed by the hirer now." >&2
  exit 1
fi

DELIVERABLE=$(cast keccak "$DELIVERABLE_TEXT")

say "what this will cost"
BALANCE=$(cast balance "$SIGNER" --rpc-url "$RPC")
GAS_PRICE=$(cast gas-price --rpc-url "$RPC")
GAS=$(cast estimate "$KERNEL" 'submit(uint256,bytes32,bytes)' "$JOB_ID" "$DELIVERABLE" 0x \
  --from "$SIGNER" --rpc-url "$RPC")
COST=$((GAS * GAS_PRICE))
echo "  chain       $CHAIN_ID"
echo "  signer      $SIGNER"
echo "  balance     $(cast to-unit "$BALANCE" ether) BNB"
echo "  deliverable $DELIVERABLE"
echo "              keccak256 of: $DELIVERABLE_TEXT"
echo "  gas         $GAS at $(cast to-unit "$GAS_PRICE" gwei) gwei"
echo "  cost        $(cast to-unit "$COST" ether) BNB"

if [ "$BALANCE" -lt "$COST" ]; then
  echo "the provider cannot pay for this. Fund $SIGNER and try again." >&2
  exit 1
fi

if [ "$ASSUME_YES" != "1" ]; then
  printf '\nSubmit this delivery? The hirer can then accept and release the escrow. [y/N] '
  read -r answer
  case "$answer" in y|Y|yes|YES) ;; *) echo "nothing was sent"; exit 1 ;; esac
fi

say "submit"
# The first real mainnet delivery landed on chain while this script reported
# nothing, because cast send could not read the receipt back and that looked
# like a failure. send_and_wait keeps the hash whatever the node does next.
set +e
send_and_wait "$RPC" "$KEY" "$KERNEL" 'submit(uint256,bytes32,bytes)' "$JOB_ID" "$DELIVERABLE" 0x
rc=$?
set -e
if [ "$rc" = "2" ]; then
  echo "job $JOB_ID may already be delivered. Check the hash above before resending." >&2
  exit 2
fi
[ "$rc" = "0" ] || exit 1
TX=$TX_HASH; BLOCK=$TX_BLOCK; GAS_USED=$TX_GAS_USED

say "delivered"
echo "  job       $JOB_ID"
echo "  tx        $TX"
echo "  block     $BLOCK"
echo "  gas used  $GAS_USED"
if is_real_mainnet; then
  echo "  bscscan   https://bscscan.com/tx/$TX"
  bash scripts/log_tx.sh "submit delivery for job $JOB_ID" "$TX" "$BLOCK" "$GAS_USED"
fi
echo
echo "The hirer can now accept from the job panel, which releases the escrow."

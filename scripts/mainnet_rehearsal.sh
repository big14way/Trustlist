#!/usr/bin/env bash
# Rehearse the entire mainnet plan against a fork of BSC, so the real run is
# a repeat rather than a first attempt.
#
# Everything here talks to the real deployed contracts: the real ERC-8004
# Identity Registry, the real ERC-8183 kernel, the real PancakeSwap router,
# the real payment token. Only the chain is a copy, and the only fake thing
# about it is that we can hand ourselves BNB.
#
# It runs the same scripts the mainnet run will use, in the same order:
#
#   1. deploy TrustListHook and HireRail
#   2. register one of our own agents, so a job has a provider we can sign for
#   3. buy the payment token with BNB
#   4. approve and hire, exactly the two transactions the web app signs
#   5. deliver as the provider, which the web app cannot do
#   6. accept, which releases the escrow
#
# It then checks the money actually moved and prints the gas each step used.
#
# Usage: scripts/mainnet_rehearsal.sh [--rpc URL] [--port N] [--keep]
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
load_env_files

# Forking needs something the ordinary read endpoints do not provide. anvil
# pins a block and then keeps reading state at that block while the real
# chain moves on, so every read becomes an archive request within seconds.
# Measured 30 August 2026: publicnode, the bnbchain data seed, blockrazor,
# 1rpc, defibit and meowrpc all serve state 20 blocks back and refuse 200.
# bloXroute, which does serve archive eth_getLogs, answers "not supported"
# for archive state. These two serve state 50,000 blocks back.
FORK_RPC="${BSC_FORK_RPC:-}"
FORK_CANDIDATES="https://bsc-mainnet.public.blastapi.io https://bsc.drpc.org"
PORT=8546
AGENT_PORT=8099
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --rpc) FORK_RPC=$2; shift 2 ;;
    --port) PORT=$2; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done

RPC="http://127.0.0.1:$PORT"

# Anvil's first well known development account, playing the visitor who
# arrives with a browser wallet. Public by design and only ever used on a
# throwaway chain.
HIRER_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
HIRER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# The real deployer, playing itself: it deploys, it registers the agent, and
# because it owns the agent it is also the provider who signs the delivery.
: "${DEPLOYER_KEY:?DEPLOYER_KEY must be set, it is the account the mainnet run will use}"
DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_KEY")

U_TOKEN=0xcE24439F2D9C6a2289F741120FE202248B666666
WBNB=0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c
PANCAKE_ROUTER=0x10ED43C718714eb63d5aA57B78B54704E256024E

ANVIL_PID=""
AGENT_PID=""
cleanup() {
  [ -n "$AGENT_PID" ] && kill "$AGENT_PID" 2>/dev/null || true
  if [ -n "$ANVIL_PID" ] && [ "$KEEP" != "1" ]; then
    kill "$ANVIL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

say()  { printf '\n==> %s\n' "$1"; }
fail() { echo "REHEARSAL FAILED: $*" >&2; exit 1; }

say "find an rpc that can serve a fork"
# A provider that cannot answer a state read at a block a few hundred deep
# will fail partway through with a wall of 403s, which is a confusing way to
# learn this. Check first, in one call, and say so plainly.
archive_ok() {
  local url=$1 head back
  head=$(cast block-number --rpc-url "$url" 2>/dev/null) || return 1
  back=$((head - 1000))
  cast balance 0x0000000000000000000000000000000000000001 \
    --block "$back" --rpc-url "$url" >/dev/null 2>&1
}
if [ -n "$FORK_RPC" ]; then
  archive_ok "$FORK_RPC" || fail "BSC_FORK_RPC=$FORK_RPC cannot serve archive state reads"
else
  for candidate in $FORK_CANDIDATES; do
    if archive_ok "$candidate"; then FORK_RPC=$candidate; break; fi
  done
  [ -n "$FORK_RPC" ] || fail "no rpc in the candidate list can serve archive state. Set BSC_FORK_RPC to one that can"
fi
echo "  using $FORK_RPC"

say "fork BSC mainnet on $RPC"
if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
  fail "something is already listening on port $PORT"
fi
# Pin a block slightly behind head. A fork pinned at the tip races the chain,
# and reorgs at the tip would change what we are testing against mid run.
PIN=$(( $(cast block-number --rpc-url "$FORK_RPC") - 20 ))
nohup anvil --fork-url "$FORK_RPC" --fork-block-number "$PIN" --port "$PORT" \
  --no-rate-limit --silent > /tmp/rehearsal-anvil.log 2>&1 &
ANVIL_PID=$!
for _ in $(seq 1 60); do
  cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break
  sleep 1
done
cast block-number --rpc-url "$RPC" >/dev/null 2>&1 \
  || { tail -20 /tmp/rehearsal-anvil.log >&2; fail "anvil did not come up"; }
FORK_BLOCK=$(cast block-number --rpc-url "$RPC")
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
[ "$CHAIN_ID" = "56" ] || fail "forked chain reports id $CHAIN_ID, expected 56"
echo "  block $FORK_BLOCK, chain $CHAIN_ID"

# 0.05 BNB each, which is far more than the plan needs. The point of the
# rehearsal is to prove the sequence, not to prove the budget; the budget is
# measured from the gas each step actually burns and printed at the end.
say "fund the two accounts on the fork"
for who in "$DEPLOYER" "$HIRER"; do
  cast rpc anvil_setBalance "$who" 0xB1A2BC2EC50000 --rpc-url "$RPC" >/dev/null
done
echo "  deployer $DEPLOYER"
echo "  hirer    $HIRER"

say "1. deploy TrustListHook and HireRail"
DEPLOY_OUT=$(cd contracts && DEPLOYER_KEY="$DEPLOYER_KEY" \
  forge script script/Deploy.s.sol:Deploy --rpc-url "$RPC" --broadcast 2>&1) \
  || { echo "$DEPLOY_OUT" | tail -30 >&2; fail "deploy reverted"; }
RAIL=$(printf '%s' "$DEPLOY_OUT" | awk '/HireRail  /{print $2; exit}')
HOOK=$(printf '%s' "$DEPLOY_OUT" | awk '/TrustListHook /{print $2; exit}')
[ -n "$RAIL" ] || { echo "$DEPLOY_OUT" | tail -30 >&2; fail "could not read the HireRail address"; }
echo "  HireRail      $RAIL"
echo "  TrustListHook $HOOK"

say "2. register our own agent"
python3 agents/pancake-yield/server.py --port "$AGENT_PORT" > /tmp/rehearsal-agent.log 2>&1 &
AGENT_PID=$!
CARD_URL="http://127.0.0.1:$AGENT_PORT/.well-known/agent-card.json"
for _ in $(seq 1 30); do
  curl -sf -o /dev/null "$CARD_URL" && break
  sleep 1
done
curl -sf -o /dev/null "$CARD_URL" \
  || { tail -20 /tmp/rehearsal-agent.log >&2; fail "the agent did not serve its card"; }

REGISTER_OUT=$(bash scripts/register_agent.sh "$CARD_URL" --rpc "$RPC" --allow-local --yes 2>&1) \
  || { echo "$REGISTER_OUT" >&2; fail "registration failed"; }
AGENT_ID=$(printf '%s' "$REGISTER_OUT" | awk '/agent id/{print $3; exit}')
[ -n "$AGENT_ID" ] || { echo "$REGISTER_OUT" >&2; fail "could not read the new agent id"; }
echo "  agent id $AGENT_ID, owned by $DEPLOYER"

OWNER=$(cast call "${IDENTITY_REGISTRY:?}" 'ownerOf(uint256)(address)' "$AGENT_ID" --rpc-url "$RPC")
[ "$(printf '%s' "$OWNER" | tr 'A-Z' 'a-z')" = "$(printf '%s' "$DEPLOYER" | tr 'A-Z' 'a-z')" ] \
  || fail "the registry says agent $AGENT_ID is owned by $OWNER, not by us"

say "3. buy the payment token with BNB"
DEADLINE=$(( $(cast block latest --field timestamp --rpc-url "$RPC") + 600 ))
cast send "$PANCAKE_ROUTER" \
  'swapExactETHForTokens(uint256,address[],address,uint256)' \
  0 "[$WBNB,$U_TOKEN]" "$HIRER" "$DEADLINE" \
  --value 2000000000000000 --private-key "$HIRER_KEY" --rpc-url "$RPC" --json > /tmp/rehearsal-swap.json
U_HELD=$(cast call "$U_TOKEN" 'balanceOf(address)(uint256)' "$HIRER" --rpc-url "$RPC" | awk '{print $1}')
[ "$U_HELD" != "0" ] || fail "the swap produced no U"
echo "  hirer holds $(cast to-unit "$U_HELD" ether) U for 0.002 BNB"

# One whole token, which is what a demo budget should look like on screen.
BUDGET=1000000000000000000
[ "$U_HELD" -ge "$BUDGET" ] || fail "0.002 BNB bought less than 1 U, raise the swap"

say "4. approve and hire, the two transactions the web app signs"
APPROVE_GAS=$(cast send "$U_TOKEN" 'approve(address,uint256)' "$RAIL" "$BUDGET" \
  --private-key "$HIRER_KEY" --rpc-url "$RPC" --json \
  | python3 -c 'import json,sys;print(int(str(json.load(sys.stdin)["gasUsed"]),16))')

JOB_DEADLINE=$(( $(cast block latest --field timestamp --rpc-url "$RPC") + 86400 ))
SPEC="Rank the three best USDT pools on PancakeSwap V3 by risk adjusted return"
HIRE_RECEIPT=$(cast send "$RAIL" \
  'hire(uint256,address,uint256,uint64,bytes32,string,uint8)' \
  "$AGENT_ID" "$DEPLOYER" "$BUDGET" "$JOB_DEADLINE" "$(cast keccak "$SPEC")" "$SPEC" 0 \
  --private-key "$HIRER_KEY" --rpc-url "$RPC" --json)
# The kernel and the token both emit during a hire, so read the job id off
# HireRail's own event rather than guessing which log carried it.
read -r HIRE_GAS JOB_ID < <(python3 - "$RAIL" "$HIRE_RECEIPT" <<'PYEOF'
import json, sys
rail = sys.argv[1].lower()
r = json.loads(sys.argv[2])
if int(str(r["status"]), 16) != 1:
    sys.exit("the hire transaction reverted")
# Hired(uint256 indexed jobId, uint256 indexed agentId, ...) is the only
# event HireRail itself emits during a hire.
ours = [l for l in r["logs"] if l["address"].lower() == rail]
if len(ours) != 1:
    sys.exit(f"expected one HireRail event, found {len(ours)}")
print(int(str(r["gasUsed"]), 16), int(ours[0]["topics"][1], 16))
PYEOF
)
echo "  job $JOB_ID funded with $(cast to-unit "$BUDGET" ether) U"

say "5. deliver as the provider"
# The kernel comes off the rail we just deployed, not out of .env, which on
# a developer machine usually still points at a dev chain.
RAIL_KERNEL=$(cast call "$RAIL" 'kernel()(address)' --rpc-url "$RPC")
DELIVER_OUT=$(PROVIDER_KEY="$DEPLOYER_KEY" bash scripts/agent_deliver.sh "$JOB_ID" \
  "three pools ranked, reasoning attached" --rpc "$RPC" --kernel "$RAIL_KERNEL" --yes 2>&1) \
  || { echo "$DELIVER_OUT" >&2; fail "the provider could not submit"; }
SUBMIT_GAS=$(printf '%s' "$DELIVER_OUT" | awk '/gas used/{print $3; exit}')
echo "  submitted, $SUBMIT_GAS gas"

say "6. accept, which releases the escrow"
BEFORE=$(cast call "$U_TOKEN" 'balanceOf(address)(uint256)' "$DEPLOYER" --rpc-url "$RPC" | awk '{print $1}')
ACCEPT_GAS=$(cast send "$RAIL" 'accept(uint256)' "$JOB_ID" \
  --private-key "$HIRER_KEY" --rpc-url "$RPC" --json \
  | python3 -c 'import json,sys
r=json.load(sys.stdin)
if int(str(r["status"]),16)!=1: sys.exit("accept reverted")
print(int(str(r["gasUsed"]),16))')
AFTER=$(cast call "$U_TOKEN" 'balanceOf(address)(uint256)' "$DEPLOYER" --rpc-url "$RPC" | awk '{print $1}')
PAID=$((AFTER - BEFORE))

say "check the money moved"
[ "$PAID" = "$BUDGET" ] \
  || fail "provider received $(cast to-unit "$PAID" ether) U, expected $(cast to-unit "$BUDGET" ether)"
RAIL_HOLDS=$(cast call "$U_TOKEN" 'balanceOf(address)(uint256)' "$RAIL" --rpc-url "$RPC" | awk '{print $1}')
[ "$RAIL_HOLDS" = "0" ] || fail "the rail is still holding $(cast to-unit "$RAIL_HOLDS" ether) U"
echo "  provider was paid $(cast to-unit "$PAID" ether) U in full, the rail holds nothing"

# The demo is very likely to be run from a single imported wallet: the same
# address deploys, owns the agent, hires it, delivers, and accepts. Nothing
# in HireRail forbids hirer == provider, but the kernel is not our contract,
# so this is tested rather than reasoned about. It is also the cheapest
# arrangement, because the budget returns to the address it left.
say "7. the same wallet as both hirer and provider"
SOLO_BEFORE=$(cast call "$U_TOKEN" 'balanceOf(address)(uint256)' "$DEPLOYER" --rpc-url "$RPC" | awk '{print $1}')
[ "$SOLO_BEFORE" -ge "$BUDGET" ] || fail "the deployer should be holding the budget it was just paid"

cast send "$U_TOKEN" 'approve(address,uint256)' "$RAIL" "$BUDGET" \
  --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" --json > /dev/null

SOLO_DEADLINE=$(( $(cast block latest --field timestamp --rpc-url "$RPC") + 86400 ))
SOLO_SPEC="Same wallet on both sides, which is how the demo will be run"
SOLO_RECEIPT=$(cast send "$RAIL" \
  'hire(uint256,address,uint256,uint64,bytes32,string,uint8)' \
  "$AGENT_ID" "$DEPLOYER" "$BUDGET" "$SOLO_DEADLINE" "$(cast keccak "$SOLO_SPEC")" "$SOLO_SPEC" 0 \
  --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" --json) \
  || fail "a hire where the hirer is also the provider was rejected"
SOLO_JOB=$(python3 - "$RAIL" "$SOLO_RECEIPT" <<'PYEOF'
import json, sys
rail = sys.argv[1].lower()
r = json.loads(sys.argv[2])
if int(str(r["status"]), 16) != 1:
    sys.exit("the one wallet hire reverted")
ours = [l for l in r["logs"] if l["address"].lower() == rail]
if len(ours) != 1:
    sys.exit(f"expected one HireRail event, found {len(ours)}")
print(int(ours[0]["topics"][1], 16))
PYEOF
)
echo "  job $SOLO_JOB opened, hirer and provider are both $DEPLOYER"

PROVIDER_KEY="$DEPLOYER_KEY" bash scripts/agent_deliver.sh "$SOLO_JOB" \
  "delivered by the same wallet that hired" --rpc "$RPC" --kernel "$RAIL_KERNEL" --yes > /dev/null \
  || fail "the one wallet provider could not submit"

cast send "$RAIL" 'accept(uint256)' "$SOLO_JOB" \
  --private-key "$DEPLOYER_KEY" --rpc-url "$RPC" --json > /dev/null \
  || fail "accept failed on the one wallet job"

SOLO_AFTER=$(cast call "$U_TOKEN" 'balanceOf(address)(uint256)' "$DEPLOYER" --rpc-url "$RPC" | awk '{print $1}')
[ "$SOLO_AFTER" = "$SOLO_BEFORE" ] \
  || fail "one wallet round trip lost tokens: $SOLO_BEFORE before, $SOLO_AFTER after"
echo "  completed, and the budget came back: $(cast to-unit "$SOLO_AFTER" ether) U before and after"

say "what the real run will cost"
GAS_PRICE=$(cast gas-price --rpc-url "$FORK_RPC")
REGISTER_GAS=$(printf '%s' "$REGISTER_OUT" | awk '/^  gas /{print $2; exit}')
DEMO_GAS=$((APPROVE_GAS + HIRE_GAS + SUBMIT_GAS + ACCEPT_GAS))
printf '  %-28s %10s\n' "register the agent" "$REGISTER_GAS"
printf '  %-28s %10s\n' "approve U" "$APPROVE_GAS"
printf '  %-28s %10s\n' "hire" "$HIRE_GAS"
printf '  %-28s %10s\n' "submit" "$SUBMIT_GAS"
printf '  %-28s %10s\n' "accept" "$ACCEPT_GAS"
printf '  %-28s %10s\n' "one hire, end to end" "$DEMO_GAS"
echo "  at $(cast to-unit "$GAS_PRICE" gwei) gwei that hire costs $(cast to-unit $((DEMO_GAS * GAS_PRICE)) ether) BNB"

echo
echo "REHEARSAL PASSED"
echo "Forked from $FORK_RPC at block $FORK_BLOCK. Nothing here touched mainnet."
[ "$KEEP" = "1" ] && echo "The fork is still running on $RPC (pid $ANVIL_PID)."
exit 0

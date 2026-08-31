#!/usr/bin/env bash
# Register one of our own agents on the ERC-8004 Identity Registry.
#
# Why this exists: a hire that completes needs a provider who can sign, and
# the provider is whatever address owns the agent. Every agent already in the
# registry is owned by a stranger, so the only job we can carry all the way
# to a payout is one against an agent we registered ourselves. That is also
# the PancakeSwap track deliverable, so it is the same work either way.
#
# The card URL is fetched and checked before anything is signed. A
# registration pointing at a URL that does not serve a usable card costs gas
# to make and gas to fix: the token is minted for good, and our own prober
# marks the agent dormant until the URI is corrected with setAgentURI.
#
# Usage:
#   scripts/register_agent.sh <card_url> [options]
#
# Options:
#   --rpc URL       chain to register on (default BSC_RPC_HTTP)
#   --key NAME      env var holding the signing key (default DEPLOYER_KEY)
#   --allow-local   permit a card URL that resolves to a private address.
#                   Only for a fork rehearsal against an agent on localhost.
#   --yes           skip the confirmation prompt
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
# shellcheck disable=SC1091
source scripts/chainlib.sh
load_env_files

CARD_URL=""
RPC=""
KEY_VAR="DEPLOYER_KEY"
ALLOW_LOCAL=0
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --rpc) RPC=$2; shift 2 ;;
    --key) KEY_VAR=$2; shift 2 ;;
    --allow-local) ALLOW_LOCAL=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 1 ;;
    *) [ -z "$CARD_URL" ] || { echo "give exactly one card url" >&2; exit 1; }
       CARD_URL=$1; shift ;;
  esac
done

[ -n "$CARD_URL" ] || { sed -n '15,24p' "$0"; exit 1; }

RPC="${RPC:-${BSC_RPC_HTTP:-}}"
[ -n "$RPC" ] || { echo "no rpc: pass --rpc or set BSC_RPC_HTTP" >&2; exit 1; }

REGISTRY="${IDENTITY_REGISTRY:?IDENTITY_REGISTRY must be set}"
KEY="${!KEY_VAR:-}"
[ -n "$KEY" ] || { echo "$KEY_VAR is empty, so there is nothing to sign with" >&2; exit 1; }

say() { printf '\n==> %s\n' "$1"; }

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

say "check the card before signing anything"
# The URL is an input that becomes a request, so it gets the same treatment
# the prober gives one: no private address ranges unless explicitly allowed,
# and a bounded timeout. Then the card itself has to be usable, because a
# registration cannot be taken back.
CARD_SUMMARY=$(ALLOW_LOCAL="$ALLOW_LOCAL" python3 - "$CARD_URL" <<'PY'
import ipaddress, json, os, socket, sys, urllib.error, urllib.request
from urllib.parse import urlparse

url = sys.argv[1]
allow_local = os.environ.get("ALLOW_LOCAL") == "1"
parsed = urlparse(url)

if parsed.scheme not in ("http", "https"):
    sys.exit(f"card url must be http or https, got {parsed.scheme!r}")
if parsed.scheme == "http" and not allow_local:
    sys.exit("card url must be https. Our prober scores plain http as a weak endpoint")
if not parsed.hostname:
    sys.exit("card url has no host")

try:
    infos = socket.getaddrinfo(parsed.hostname, parsed.port or (443 if parsed.scheme == "https" else 80))
except socket.gaierror as e:
    sys.exit(f"card url host does not resolve: {e}")

for info in infos:
    ip = ipaddress.ip_address(info[4][0])
    if (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved) and not allow_local:
        sys.exit(f"card url resolves to {ip}, a private address. Pass --allow-local only for a fork rehearsal")

try:
    with urllib.request.urlopen(url, timeout=10) as r:
        if r.status != 200:
            sys.exit(f"card url returned {r.status}")
        body = r.read(1 << 20)
except urllib.error.URLError as e:
    sys.exit(f"card url did not answer: {e}")

try:
    card = json.loads(body)
except json.JSONDecodeError as e:
    sys.exit(f"card is not valid json: {e}")
if not isinstance(card, dict):
    sys.exit("card is not a json object")

name = card.get("name")
if not isinstance(name, str) or not name.strip():
    sys.exit("card has no name, so the marketplace would list it as unnamed")

# crates/prober/src/card.rs accepts three shapes. Mirror what it will find,
# so this refuses exactly the cards that would index as endpointless.
endpoints = []
for s in card.get("services") or []:
    if isinstance(s, dict) and str(s.get("endpoint", "")).startswith("http"):
        endpoints.append(s["endpoint"])
for e in card.get("endpoints") or []:
    if isinstance(e, str) and e.startswith("http"):
        endpoints.append(e)
    elif isinstance(e, dict) and str(e.get("url", "")).startswith("http"):
        endpoints.append(e["url"])
if isinstance(card.get("url"), str) and card["url"].startswith("http"):
    endpoints.append(card["url"])

if not endpoints:
    sys.exit("card lists no http endpoint, so the prober would have nothing to probe")

relative = [e for e in endpoints if urlparse(e).hostname is None]
if relative:
    sys.exit(f"card endpoints must be absolute urls, got {relative[0]!r}")

print(json.dumps({"name": name, "endpoints": endpoints}))
PY
)
CARD_NAME=$(printf '%s' "$CARD_SUMMARY" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
echo "  name      $CARD_NAME"
printf '%s' "$CARD_SUMMARY" \
  | python3 -c 'import json,sys
for e in json.load(sys.stdin)["endpoints"]: print("  endpoint ", e)'

say "what this will cost"
SIGNER=$(cast wallet address --private-key "$KEY")
CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
BALANCE=$(cast balance "$SIGNER" --rpc-url "$RPC")
GAS_PRICE=$(cast gas-price --rpc-url "$RPC")
GAS=$(cast estimate "$REGISTRY" "register(string)" "$CARD_URL" --from "$SIGNER" --rpc-url "$RPC")
COST=$((GAS * GAS_PRICE))
echo "  chain     $CHAIN_ID"
echo "  registry  $REGISTRY"
echo "  signer    $SIGNER"
echo "  balance   $(cast to-unit "$BALANCE" ether) BNB"
echo "  gas       $GAS at $(cast to-unit "$GAS_PRICE" gwei) gwei"
echo "  cost      $(cast to-unit "$COST" ether) BNB"

if [ "$BALANCE" -lt "$COST" ]; then
  echo "the signer cannot pay for this. Fund $SIGNER and try again." >&2
  exit 1
fi

if [ "$ASSUME_YES" != "1" ]; then
  printf '\nThis mints an agent token to the signer, for good. Continue? [y/N] '
  read -r answer
  case "$answer" in y|Y|yes|YES) ;; *) echo "nothing was sent"; exit 1 ;; esac
fi

say "register"
# A registration that landed but was reported as failed is the worst case
# here: resending mints a second agent and pays for it. Keep the hash.
set +e
send_and_wait "$RPC" "$KEY" "$REGISTRY" "register(string)" "$CARD_URL"
rc=$?
set -e
if [ "$rc" = "2" ]; then
  echo "an agent may already have been minted. Check the hash above before resending." >&2
  exit 2
fi
[ "$rc" = "0" ] || exit 1
TX=$TX_HASH; BLOCK=$TX_BLOCK; GAS=$TX_GAS_USED

# The agent id comes from the Registered event, read back from the chain
# rather than from the send, for the same reason.
AGENT_ID=$(cast receipt "$TX" --rpc-url "$RPC" --json | python3 -c '
import json, sys
r = json.load(sys.stdin)
# Registered(uint256 indexed agentId, string agentURI, address indexed owner),
# topic0 pinned in crates/indexer/src/events.rs.
TOPIC0 = "0xca52e62c367d81bb2e328eb795f7c7ba24afb478408a26c0e201d155c449bc4a"
ids = [int(log["topics"][1], 16) for log in r["logs"]
       if log["topics"] and log["topics"][0].lower() == TOPIC0]
if len(ids) != 1:
    sys.exit(f"expected exactly one Registered event, found {len(ids)}")
print(ids[0])
')

say "registered"
echo "  agent id  $AGENT_ID"
echo "  owner     $SIGNER"
echo "  tx        $TX"
echo "  block     $BLOCK"
if is_real_mainnet; then
  echo "  bscscan   https://bscscan.com/tx/$TX"
  echo "  8004scan  https://8004scan.io/agents/bsc/$AGENT_ID"
  bash scripts/log_tx.sh "register $CARD_NAME as agent $AGENT_ID" "$TX" "$BLOCK" "$GAS"
fi
echo
echo "Our indexer picks this up on its next pass over the registry. Until then"
echo "the agent will not appear in the marketplace."
echo
echo "To point the agent at a different card later:"
echo "  cast send $REGISTRY 'setAgentURI(uint256,string)' $AGENT_ID <url> \\"
echo "    --private-key \$DEPLOYER_KEY --rpc-url \$BSC_RPC_HTTP"

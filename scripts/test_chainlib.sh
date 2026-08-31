#!/usr/bin/env bash
# Prove that a transaction which lands on chain is never reported as a
# failure, whatever the node does with the receipt.
#
# This is not a hypothetical. It happened three times on BSC public
# endpoints, twice with real money at stake: the mainnet deploy printed
# "Some transactions were discarded by the RPC node" with both contracts
# already deployed, and the first mainnet job delivery reported nothing while
# the kernel had recorded the submission. Following either output would have
# meant paying to do the same thing twice.
#
# So the case is tested rather than trusted. A proxy in front of a local
# chain accepts transactions normally and answers every receipt request the
# way PublicNode did, with a 403. The transaction must still land, the hash
# must survive, and the caller must be told to check rather than resend.
#
# Self contained: starts its own chain and its own proxy, and cleans up.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/chainlib.sh

PORT="${CHAINLIB_TEST_PORT:-8645}"
PROXY_PORT="${CHAINLIB_TEST_PROXY_PORT:-8646}"
RPC="http://127.0.0.1:$PORT"
BAD="http://127.0.0.1:$PROXY_PORT"
# anvil's first development account. Public by design, throwaway chain only.
KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
TO=0x70997970C51812dc3A010C7d01b50e0d17dc79C8

ANVIL_PID=""; PROXY_PID=""; WORKDIR=""
cleanup() {
  [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null || true
  [ -n "$ANVIL_PID" ] && kill "$ANVIL_PID" 2>/dev/null || true
  [ -n "$WORKDIR" ] && rm -rf "$WORKDIR" || true
}
trap cleanup EXIT

FAILED=0
ok()   { echo "  ok    $1"; }
bad()  { echo "  FAIL  $1" >&2; FAILED=1; }

nohup anvil --port "$PORT" --silent > /tmp/chainlib-anvil.log 2>&1 &
ANVIL_PID=$!
for _ in $(seq 1 30); do
  cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break
  sleep 1
done
cast block-number --rpc-url "$RPC" >/dev/null 2>&1 || {
  echo "anvil did not start, see /tmp/chainlib-anvil.log" >&2; exit 1; }

WORKDIR=$(mktemp -d)
PROXY_PY="$WORKDIR/proxy.py"
cat > "$PROXY_PY" <<PY
import json, sys, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
UP = "http://127.0.0.1:$PORT"
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        req = json.loads(body)
        if isinstance(req, dict) and req.get("method") == "eth_getTransactionReceipt":
            out = json.dumps({"jsonrpc": "2.0", "id": req.get("id"), "error": {
                "code": -32602,
                "message": "Archive requests require a personal token"}}).encode()
            self.send_response(403)
        else:
            out = urllib.request.urlopen(urllib.request.Request(
                UP, body, {"content-type": "application/json"}), timeout=20).read()
            self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)
HTTPServer(("127.0.0.1", $PROXY_PORT), H).serve_forever()
PY
nohup python3 "$PROXY_PY" > /tmp/chainlib-proxy.log 2>&1 &
PROXY_PID=$!
sleep 2

echo "== chainlib =="

# 1. The ordinary case.
set +e
send_and_wait "$RPC" "$KEY" "$TO" --value 1 >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" = "0" ] && [ -n "$TX_HASH" ] && [ -n "$TX_BLOCK" ] && [ "$TX_GAS_USED" = "21000" ]; then
  ok "a mined transaction reports success, with its hash, block and gas"
else
  bad "a plain transfer should have returned 0, got $rc"
fi

# 2. A node that will not take the transaction at all. Nothing was sent, so
#    retrying is safe, and that has to be distinguishable from case 3.
set +e
send_and_wait "http://127.0.0.1:1" "$KEY" "$TO" --value 1 >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = "1" ] && ok "a refused broadcast reports failure" \
                || bad "a refused broadcast should have returned 1, got $rc"

# 3. The case that cost us twice: it is on chain, the node will not say so.
BEFORE=$(cast block-number --rpc-url "$RPC")
# Deliberately not inside $(...). Command substitution runs in a subshell,
# so the variables send_and_wait sets would never reach this scope, and the
# hash is exactly what this case is checking.
OUTFILE="$WORKDIR/out.txt"
set +e
send_and_wait "$BAD" "$KEY" "$TO" --value 1 > "$OUTFILE" 2>&1
rc=$?
set -e
OUT=$(cat "$OUTFILE")
AFTER=$(cast block-number --rpc-url "$RPC")

[ "$rc" = "2" ] && ok "an unreadable receipt is its own outcome, not a failure" \
                || bad "an unreadable receipt should have returned 2, got $rc"

case "$TX_HASH" in
  0x????????????????????????????????????????????????????????????????)
    ok "the hash survives, so the transaction can still be looked up" ;;
  *) bad "the hash was lost, which is the whole thing this prevents" ;;
esac

[ "$AFTER" -gt "$BEFORE" ] \
  && ok "and the transaction really did land while the node denied it" \
  || bad "the transaction did not land, so this test proved nothing"

case "$OUT" in
  *"before resending"*) ok "the caller is told to check rather than resend" ;;
  *) bad "the output does not warn against resending" ;;
esac

echo
[ "$FAILED" = "0" ] && echo "chainlib: all checks passed" || { echo "chainlib: FAILED" >&2; exit 1; }

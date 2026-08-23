#!/usr/bin/env bash
# Stand up a local hire stack: anvil, a U like token, a kernel and router
# that enforce the same rules the live ones do, and HireRail on top.
#
# This is a local development chain. HireRailFork.t.sol proves the same
# HireRail code works against the real deployed mainnet contracts, and the
# agents shown in the product always come from the real registry index.
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${DEVCHAIN_PORT:-8545}"
# anvil's first well known development account. Public by design.
DEV_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

pkill -f "anvil --port $PORT" 2>/dev/null || true
sleep 1
nohup anvil --port "$PORT" --chain-id 31337 --silent > /tmp/anvil.log 2>&1 &
until cast block-number --rpc-url "http://localhost:$PORT" >/dev/null 2>&1; do sleep 1; done

OUT=$(cd contracts && DEPLOYER_KEY="$DEV_KEY" \
  forge script script/DevChain.s.sol:DevChain \
  --rpc-url "http://localhost:$PORT" --broadcast 2>&1)

echo "$OUT" | grep -E "^  DEV_" | sed 's/^  //' > .devchain.env
if [ ! -s .devchain.env ]; then
  echo "dev chain deploy failed:" >&2
  echo "$OUT" | tail -20 >&2
  exit 1
fi
cat .devchain.env

# Point the services and the web app at it.
RAIL=$(grep '^DEV_HIRE_RAIL=' .devchain.env | cut -d= -f2)
TOKEN=$(grep '^DEV_TOKEN=' .devchain.env | cut -d= -f2)
KERNEL=$(grep '^DEV_KERNEL=' .devchain.env | cut -d= -f2)

python3 - "$RAIL" "$TOKEN" "$KERNEL" "$PORT" <<'PY'
import sys, os, re
rail, token, kernel, port = sys.argv[1:5]
rpc = f"http://localhost:{port}"

def upsert(path, values, header=None):
    lines = []
    if os.path.exists(path):
        lines = open(path).read().splitlines()
    for k, v in values.items():
        pat = re.compile(rf"^{re.escape(k)}=")
        for i, line in enumerate(lines):
            if pat.match(line):
                lines[i] = f"{k}={v}"
                break
        else:
            lines.append(f"{k}={v}")
    body = "\n".join(lines).strip() + "\n"
    if header and not body.startswith("#"):
        body = header + body
    open(path, "w").write(body)

upsert(".env", {
    "HIRE_RAIL": rail,
    "HIRE_RAIL_RPC": rpc,
    "HIRE_RAIL_CHAIN_ID": "31337",
    "HIRE_RAIL_KERNEL": kernel,
    "HIRE_RAIL_DEPLOY_BLOCK": "0",
})
upsert("web/.env.local", {
    "NEXT_PUBLIC_CHAIN_ID": "31337",
    "NEXT_PUBLIC_API_URL": "http://localhost:8080",
    "NEXT_PUBLIC_HIRE_RAIL": rail,
    "NEXT_PUBLIC_PAYMENT_TOKEN": token,
})
print("wrote .env and web/.env.local")
PY
echo "dev chain ready on http://localhost:$PORT"

#!/usr/bin/env bash
# Regenerate the web app's contract ABI from the compiled artifact so the
# frontend can never drift from the deployed contract.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd contracts && forge build >/dev/null)
python3 - <<'PY'
import json
art = json.load(open('contracts/out/HireRail.sol/HireRail.json'))
keep = [i for i in art['abi'] if i.get('type') in ('function','event','error')]
ts = "// Generated from contracts/out/HireRail.sol/HireRail.json. Do not hand edit.\n"
ts += "// Regenerate with: bash scripts/gen_abi.sh\n\n"
ts += "export const hireRailAbi = " + json.dumps(keep, indent=2) + " as const;\n"
open('web/lib/hireRailAbi.ts','w').write(ts)
print("regenerated web/lib/hireRailAbi.ts")
PY

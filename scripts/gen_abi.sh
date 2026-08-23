#!/usr/bin/env bash
# Regenerate the web app's contract ABI from the compiled artifact so the
# frontend can never drift from the deployed contract.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd contracts && forge build >/dev/null)
python3 - <<'PY'
import json
def emit(artifact, name, out):
    art = json.load(open(artifact))
    keep = [i for i in art['abi'] if i.get('type') in ('function', 'event', 'error')]
    ts = "// Generated from %s. Do not hand edit.\n" % artifact
    ts += "// Regenerate with: bash scripts/gen_abi.sh\n\n"
    ts += "export const %s = " % name + json.dumps(keep, indent=2) + " as const;\n"
    open(out, 'w').write(ts)
    print("regenerated", out)

emit('contracts/out/HireRail.sol/HireRail.json', 'hireRailAbi', 'web/lib/hireRailAbi.ts')
emit('contracts/out/TrustSnapshot.sol/TrustSnapshot.json', 'trustSnapshotAbi', 'web/lib/trustSnapshotAbi.ts')
PY

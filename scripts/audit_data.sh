#!/usr/bin/env bash
# The data honesty audit. SPEC Section 29.3.
#
# Passing a lint gate does not prove the numbers on screen are true. This
# script takes live data and re-derives it independently: chain reads go
# through a different RPC than the indexer uses, the trust score is
# recomputed from the raw feedback rows, and the Merkle root is rebuilt with
# a different keccak implementation than the one that built it.
#
# Every check prints expected versus actual. The table goes in
# docs/SUBMISSION.md.
set -uo pipefail
cd "$(dirname "$0")/.."

set -a
# shellcheck disable=SC1091
source .env.example
[ -f .env ] && source .env
set +a

API="${AUDIT_API:-http://localhost:8080}"
# Deliberately not the indexer's RPC. If the indexer's provider were lying to
# us, checking against the same provider would not notice.
AUDIT_RPC="${AUDIT_RPC:-https://bsc-rpc.publicnode.com}"
IDENTITY="${IDENTITY_REGISTRY:-0x8004A169FB4a3325136EB29fA0ceB6D2e539a432}"
# ERC-7201 namespaced storage, first struct member _lastId. The registry is
# ERC-721 but not Enumerable, so there is no totalSupply to ask for.
LAST_ID_SLOT=0xa040f782729de4970518741823ec1276cbcd41a0c7493f62d173341566a04e00
SNAPSHOT_RPC="${SNAPSHOT_RPC:-${HIRE_RAIL_RPC:-http://localhost:8545}}"
SNAPSHOT_ADDR="${TRUST_SNAPSHOT:-}"

PASS=0
FAIL=0
SKIP=0
ROWS=()

row() { ROWS+=("$1|$2|$3|$4"); }
ok()   { PASS=$((PASS+1)); row "$1" "$2" "$3" "pass"; }
bad()  { FAIL=$((FAIL+1)); row "$1" "$2" "$3" "FAIL"; }
skip() { SKIP=$((SKIP+1)); row "$1" "$2" "$3" "skipped"; }

psql_q() {
  docker compose exec -T db psql -U trustlist -d trustlist -tAc "$1" 2>/dev/null
}

say() { printf "\n--- %s\n" "$1"; }

if ! curl -sf "$API/v1/health" >/dev/null; then
  echo "api is not up at $API, start it with make demo" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
say "1. five agents: the card on chain matches what the API serves"
# ---------------------------------------------------------------------------
SAMPLE=$(curl -sf "$API/v1/agents?limit=60" \
  | python3 -c "
import json, sys, random
items = json.load(sys.stdin).get('items', [])
random.shuffle(items)
for a in items[:5]:
    print(a['agent_id'], (a.get('name') or '').replace('|', ' '), sep='|')
" 2>/dev/null)

if [ -z "$SAMPLE" ]; then
  skip "1. agent cards" "5 agents checked" "no agents returned"
else
  while IFS='|' read -r AID API_NAME; do
    [ -n "$AID" ] || continue
    URI=$(cast call "$IDENTITY" "tokenURI(uint256)(string)" "$AID" --rpc-url "$AUDIT_RPC" 2>/dev/null | tr -d '"')
    if [ -z "$URI" ]; then
      skip "1. agent $AID" "tokenURI from chain" "chain read failed"
      continue
    fi
    case "$URI" in
      https://*)
        CARD=$(curl -sf -m 15 "$URI" 2>/dev/null)
        if [ -z "$CARD" ]; then
          skip "1. agent $AID" "card name" "card unreachable now"
          continue
        fi
        CARD_NAME=$(printf '%s' "$CARD" | python3 -c "
import json,sys
try: print((json.load(sys.stdin).get('name') or '').strip())
except Exception: print('')
" 2>/dev/null)
        if [ "$CARD_NAME" = "$(printf '%s' "$API_NAME" | sed 's/^ *//;s/ *$//')" ]; then
          ok "1. agent $AID name" "$CARD_NAME" "$API_NAME"
        else
          bad "1. agent $AID name" "$CARD_NAME" "$API_NAME"
        fi
        ;;
      *)
        # ipfs and data URIs are real and common. The indexer resolves them,
        # this audit does not fetch through a gateway it cannot vouch for.
        skip "1. agent $AID" "card name" "non-https tokenURI (${URI%%:*})"
        ;;
    esac
  done <<< "$SAMPLE"
fi

# ---------------------------------------------------------------------------
say "2. uptime_7d recomputed from probe_results"
# ---------------------------------------------------------------------------
UP_AGENT=$(psql_q "
  select agent_id from agent_scores
  where uptime_7d is not null and probes_7d >= 24
  order by computed_at desc limit 1")

if [ -z "$UP_AGENT" ]; then
  skip "2. uptime_7d" "recomputed" "no agent with enough probes"
else
  API_UP=$(curl -sf "$API/v1/agents/$UP_AGENT" \
    | python3 -c "import json,sys;print(json.load(sys.stdin).get('uptime_7d'))" 2>/dev/null)
  SQL_UP=$(psql_q "
    select round(
      count(*) filter (where ok)::numeric / nullif(count(*), 0), 6)
    from probe_results
    where agent_id = $UP_AGENT and probed_at > now() - interval '7 days'")
  DIFF=$(python3 -c "
a='${API_UP:-none}'; b='${SQL_UP:-none}'
try: print(abs(float(a)-float(b)))
except Exception: print('nan')")
  if python3 -c "import sys; sys.exit(0 if '$DIFF' != 'nan' and float('$DIFF') <= 0.001 else 1)"; then
    ok "2. uptime_7d agent $UP_AGENT" "$SQL_UP" "$API_UP"
  else
    bad "2. uptime_7d agent $UP_AGENT" "$SQL_UP" "$API_UP (diff $DIFF)"
  fi
fi

# ---------------------------------------------------------------------------
say "3. trust score recomputed by hand from feedback and reviewer weights"
# ---------------------------------------------------------------------------
TRUST_AGENT=$(psql_q "
  select agent_id from agent_trust
  where trust is not null order by feedback_kept desc limit 1")

if [ -z "$TRUST_AGENT" ]; then
  skip "3. trust score" "recomputed" "no scored agent with reviews"
else
  API_TRUST=$(curl -sf "$API/v1/agents/$TRUST_AGENT" \
    | python3 -c "import json,sys;print(json.load(sys.stdin).get('trust'))" 2>/dev/null)

  # Everything the formula needs, straight from the raw tables. The scale,
  # the prior, and the cluster cap all come from the published methodology.
  PRIOR=$(curl -sf "$API/v1/methodology" \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['reputation']['prior_strength'])")

  psql_q "copy (
    select f.agent_id, encode(f.reviewer,'hex'), f.value, f.value_decimals,
           coalesce(w.weight, 1.0), coalesce(w.cluster_id, -1)
    from feedback f
    left join reviewer_weights w on w.reviewer = f.reviewer
    where not f.revoked
  ) to stdout with (format csv)" > /tmp/audit_feedback.csv

  RECOMPUTED=$(python3 - "$TRUST_AGENT" "$PRIOR" <<'PY'
import csv, sys
from collections import defaultdict

target, prior = sys.argv[1], float(sys.argv[2])

def normalise(value, decimals):
    try:
        v = float(value) / (10 ** int(decimals))
    except Exception:
        return 0.0
    return min(max(v / 100.0, 0.0), 1.0)

rows = list(csv.reader(open('/tmp/audit_feedback.csv')))

# Population mean over all weighted evidence, which is what thin agents get
# shrunk toward.
num = den = 0.0
by_agent = defaultdict(list)
for agent_id, reviewer, value, decimals, weight, cluster in rows:
    w, s = float(weight), normalise(value, decimals)
    num += w * s
    den += w
    if agent_id == target:
        by_agent[agent_id].append((reviewer, s, w, int(cluster)))
mu = num / den if den > 0 else 0.5

items = by_agent.get(target, [])
if not items:
    print('none')
    sys.exit()

# One voice per cluster, at the weight of its strongest member.
best = defaultdict(lambda: [0.0, 0.0, 0.0])
for _reviewer, s, w, cluster in items:
    e = best[cluster]
    e[0] = max(e[0], w)
    e[1] += w * s
    e[2] += w

s_sum = w_sum = 0.0
for _cluster, (best_w, weighted, total) in best.items():
    if total <= 0:
        continue
    s_sum += best_w * (weighted / total)
    w_sum += best_w

print(f"{100.0 * ((s_sum + prior * mu) / (w_sum + prior)):.4f}" if w_sum >= 1.0 else 'none')
PY
)
  DIFF=$(python3 -c "
try: print(abs(float('${API_TRUST:-nan}') - float('${RECOMPUTED:-nan}')))
except Exception: print('nan')")
  if python3 -c "import sys; sys.exit(0 if '$DIFF' != 'nan' and float('$DIFF') <= 0.5 else 1)"; then
    ok "3. trust agent $TRUST_AGENT" "$RECOMPUTED" "$API_TRUST"
  else
    bad "3. trust agent $TRUST_AGENT" "$RECOMPUTED" "$API_TRUST (diff $DIFF)"
  fi
  rm -f /tmp/audit_feedback.csv
fi

# ---------------------------------------------------------------------------
say "4. Merkle root rebuilt from the published leaves"
# ---------------------------------------------------------------------------
curl -sf "$API/v1/snapshots/latest?payload=true" > /tmp/audit_snapshot.json
SNAP_ID=$(python3 -c "import json;print(json.load(open('/tmp/audit_snapshot.json'))['id'])" 2>/dev/null)
SERVED_ROOT=$(python3 -c "import json;print(json.load(open('/tmp/audit_snapshot.json'))['merkle_root'])" 2>/dev/null)
ONCHAIN_IDX=$(python3 -c "
import json
v=json.load(open('/tmp/audit_snapshot.json')).get('onchain_index')
print('' if v is None else v)" 2>/dev/null)

if [ -z "${SERVED_ROOT:-}" ]; then
  skip "4. merkle root" "rebuilt locally" "no snapshot published yet"
else
  # viem's keccak, not our alloy keccak. Two implementations agreeing is the
  # point of this check.
  REBUILT=$(cd web && node -e "
const { keccak256, concat } = require('viem');
const snap = require('/tmp/audit_snapshot.json');
let level = snap.payload.leaves.map(l => l.leaf);
while (level.length > 1) {
  const next = [];
  for (let i = 0; i < level.length; i += 2) {
    if (i + 1 === level.length) { next.push(level[i]); continue; }
    const [a, b] = [level[i], level[i + 1]].sort();
    next.push(keccak256(concat([a, b])));
  }
  level = next;
}
console.log(level[0]);
" 2>/dev/null)
  if [ "$REBUILT" = "$SERVED_ROOT" ]; then
    ok "4. merkle root (snapshot $SNAP_ID)" "$SERVED_ROOT" "$REBUILT"
  else
    bad "4. merkle root (snapshot $SNAP_ID)" "$SERVED_ROOT" "${REBUILT:-rebuild failed}"
  fi
fi

# ---------------------------------------------------------------------------
say "5. one leaf verified on chain against the published root"
# ---------------------------------------------------------------------------
if [ -z "$SNAPSHOT_ADDR" ]; then
  skip "5. on chain verify" "true" "TRUST_SNAPSHOT not set"
elif [ -z "${SNAP_ID:-}" ]; then
  skip "5. on chain verify" "true" "no snapshot to prove"
elif [ -z "${ONCHAIN_IDX:-}" ]; then
  skip "5. on chain verify" "true" "latest snapshot is not published on chain"
else
  LEAF_AGENT=$(python3 -c "import json;print(json.load(open('/tmp/audit_snapshot.json'))['payload']['leaves'][0]['agent_id'])")
  PROOF_JSON=$(curl -sf "$API/v1/snapshots/$SNAP_ID/proof/$LEAF_AGENT")
  eval "$(printf '%s' "$PROOF_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin); a=d['verify_args']
print(f\"P_ARGS='{a['agentId']} {a['liveness']} {a['trust']} {a['confidence']} {a['computedAt']}'\")
print('P_PROOF=\'[' + ','.join(d['proof']) + ']\'')
")"
  # The contract's own index, which the API reports. We build a snapshot
  # every cycle and publish far fewer, so it is not our id minus one.
  ONCHAIN=$(cast call "$SNAPSHOT_ADDR" \
    "verify(uint256,uint256,uint16,uint16,uint16,uint64,bytes32[])(bool)" \
    "$ONCHAIN_IDX" $P_ARGS "$P_PROOF" --rpc-url "$SNAPSHOT_RPC" 2>/dev/null | tail -1)
  if [ "$ONCHAIN" = "true" ]; then
    ok "5. verify agent $LEAF_AGENT on chain" "true" "true"
  else
    bad "5. verify agent $LEAF_AGENT on chain" "true" "${ONCHAIN:-call failed}"
  fi
fi
rm -f /tmp/audit_snapshot.json

# ---------------------------------------------------------------------------
say "6. registered count: our events, the API, and the registry's own counter"
# ---------------------------------------------------------------------------
INDEXED=$(psql_q "select count(*) from agents")
API_COUNT=$(curl -sf "$API/v1/stats" \
  | python3 -c "import json,sys;print(json.load(sys.stdin)['registered'])" 2>/dev/null)
SLOT_HEX=$(cast storage "$IDENTITY" "$LAST_ID_SLOT" --rpc-url "$AUDIT_RPC" 2>/dev/null | tail -1)
SLOT_DEC=$(python3 -c "
h='${SLOT_HEX:-}'.strip()
print(int(h,16) if h.startswith('0x') else 'none')" 2>/dev/null)

if [ "$INDEXED" = "$API_COUNT" ]; then
  ok "6a. API count matches our index" "$INDEXED" "$API_COUNT"
else
  bad "6a. API count matches our index" "$INDEXED" "$API_COUNT"
fi

if [ "${SLOT_DEC:-none}" = "none" ]; then
  skip "6b. registry _lastId cross check" "$INDEXED" "storage read failed"
else
  # Two independent methods. They are not required to be identical: the
  # counter moves between our last indexed block and the current head. The
  # diff is the artifact worth showing.
  # The counter is read at the current head, our index stops at the last
  # block we processed, so the registry is always at or ahead of us. What
  # would be alarming is us claiming more agents than the registry has, or
  # falling percentage points behind. The gap itself is the artifact.
  DELTA=$((SLOT_DEC - INDEXED))
  PCT=$(python3 -c "print(f'{100.0 * $DELTA / max($SLOT_DEC,1):.2f}')")
  if [ "$DELTA" -lt 0 ]; then
    bad "6b. registry _lastId cross check" "$SLOT_DEC" "$INDEXED (we claim MORE than the registry)"
  elif python3 -c "import sys; sys.exit(0 if float('$PCT') <= 5.0 else 1)"; then
    ok "6b. registry _lastId cross check" "$SLOT_DEC" "$INDEXED (behind head by $DELTA, $PCT%)"
  else
    bad "6b. registry _lastId cross check" "$SLOT_DEC" "$INDEXED (behind by $DELTA, $PCT%, indexer is lagging)"
  fi
fi

# ---------------------------------------------------------------------------
printf "\n\n"
echo "| check | expected | actual | result |"
echo "|---|---|---|---|"
for r in "${ROWS[@]}"; do
  IFS='|' read -r a b c d <<< "$r"
  echo "| $a | $b | $c | $d |"
done
printf "\n%s passed, %s failed, %s skipped\n" "$PASS" "$FAIL" "$SKIP"
echo "chain reads used $AUDIT_RPC, which is not the indexer's provider"

[ "$FAIL" -eq 0 ]

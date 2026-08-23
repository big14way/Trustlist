#!/usr/bin/env bash
# The completion gate, SPEC.md Section 29.2. Exits non zero on the first
# failure. Checks that only make sense once a milestone has shipped are gated
# by the number in .milestone, and thresholds only ever move up.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "GATE FAIL: $*" >&2; exit 1; }
say()  { printf '\n== %s ==\n' "$1"; }

MILESTONE=$(cat .milestone 2>/dev/null || echo 0)

# psql may not exist on the host; fall back to the compose container.
run_sql() {
  if command -v psql >/dev/null 2>&1; then
    psql "$DATABASE_URL" -tAc "$1"
  else
    docker compose exec -T db psql -U trustlist -d trustlist -tAc "$1"
  fi
}

say "1. no unfinished markers in shipped code"
if grep -rInE 'TODO|FIXME|XXX|HACK|WIP:' \
    --include='*.rs' --include='*.ts' --include='*.tsx' --include='*.sol' \
    crates/ web/app web/components web/lib contracts/src 2>/dev/null; then
  fail "unfinished markers found above"
fi

say "2. no rust stubs"
if grep -rInE 'todo!\(|unimplemented!\(|panic!\("not implemented' crates/ 2>/dev/null; then
  fail "rust stubs found above"
fi

say "3. no fake data"
if grep -rInE 'mockAgent|mockData|fakeData|dummyData|sampleAgents|placeholderAgent|lorem ipsum|0xdeadbeef|0x1234567890' \
    --include='*.rs' --include='*.ts' --include='*.tsx' \
    crates/ web/app web/components web/lib 2>/dev/null; then
  fail "mock or placeholder data found above"
fi

say "4. no swallowed errors"
if grep -rInE 'catch\s*\([^)]*\)\s*\{\s*\}|catch\s*\{\s*\}|\.catch\(\(\)\s*=>\s*\{\s*\}\)' \
    web/app web/components web/lib 2>/dev/null; then
  fail "empty catch blocks found above"
fi
if grep -rIn 'let _ = ' crates/*/src 2>/dev/null | grep -v '_ = tracing'; then
  fail "discarded results found above, handle or log them"
fi

say "5. unwrap budget in service code"
# Inline #[cfg(test)] modules are tests, not service code; awk drops
# everything from that marker to end of file before counting.
COUNT=$(find crates/api/src crates/prober/src crates/indexer/src crates/trust/src \
    -name '*.rs' 2>/dev/null \
  | grep -v '/tests/' | grep -v 'main.rs' \
  | xargs -I{} awk '/#\[cfg\(test\)\]/{exit} /\.unwrap\(\)/{count++} END{print count+0}' {} \
  | awk '{sum+=$1} END{print sum+0}')
[ "${COUNT:-0}" -le 5 ] || fail "$COUNT unwraps in service code, budget is 5"

say "6. typecheck, lint, build"
cargo clippy --workspace --all-targets -- -D warnings
cargo fmt --check
( cd web && npx tsc --noEmit && NEXT_BUILD_DIR=.next-verify npm run build )
if grep -rIn ': any\b' web/app web/components web/lib \
    --include='*.ts' --include='*.tsx' 2>/dev/null; then
  fail "any types found above"
fi

say "7. tests"
cargo test --workspace
( cd contracts && forge test -vv )
if find contracts/src -name '*.sol' | grep -q .; then
  # SPEC.md Section 14 sets the bar on src/, the code we actually ship.
  # Deploy scripts and test helpers are tooling and are reported separately
  # by forge; including them would measure the wrong thing.
  COV_REPORT=$( cd contracts && forge coverage --report summary 2>/dev/null )
  echo "$COV_REPORT" | grep -E '^\| (src/|File)' || true
  WORST=$( echo "$COV_REPORT" \
    | awk -F'|' '/^\| src\// { gsub(/%.*/,"",$3); gsub(/[^0-9.]/,"",$3); if ($3 != "") print $3 }' \
    | sort -n | head -1 )
  [ -n "$WORST" ] || fail "could not read coverage for contracts/src"
  awk -v c="$WORST" 'BEGIN { exit (c+0 >= 90) ? 0 : 1 }' \
    || fail "lowest contracts/src coverage is ${WORST}%, under 90"
  echo "lowest contracts/src line coverage: ${WORST}%"
else
  echo "no contracts yet, coverage check begins when contracts/src has source"
fi

say "8. no secrets"
if grep -rInE '(0x)?[a-fA-F0-9]{64}' --include='*.ts' --include='*.rs' --include='*.env*' \
    --exclude='*.lock' crates/ web/app web/components web/lib contracts/script 2>/dev/null \
  | grep -viE 'hash|root|digest|keccak|selector'; then
  fail "possible private key material found above"
fi
if git log --all -p | grep -qE 'PRIVATE_KEY\s*=\s*0x[a-fA-F0-9]{64}'; then
  fail "a private key exists somewhere in git history"
fi

say "9. env completeness"
for v in $(grep -oE '^[A-Z_0-9]+' .env.example); do
  grep -rq "$v" crates/ web/ contracts/script Makefile scripts/ 2>/dev/null \
    || fail "$v in .env.example is never read"
done

if [ "$MILESTONE" -ge 1 ]; then
  say "10. every documented route answers"
  for r in /v1/health /v1/stats /v1/agents; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "${API:-http://localhost:8080}$r")
    [ "$code" = "200" ] || fail "$r returned $code"
  done
  if [ "$MILESTONE" -ge 6 ]; then
    for r in /v1/snapshots/latest /v1/methodology; do
      code=$(curl -s -o /dev/null -w '%{http_code}' "${API:-http://localhost:8080}$r")
      [ "$code" = "200" ] || fail "$r returned $code"
    done
  fi
  for p in /; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "${WEB:-http://localhost:3000}$p")
    [ "$code" = "200" ] || fail "page $p returned $code"
  done
  if [ "$MILESTONE" -ge 5 ]; then
    for p in /jobs /sessions /methodology /stats; do
      code=$(curl -s -o /dev/null -w '%{http_code}' "${WEB:-http://localhost:3000}$p")
      [ "$code" = "200" ] || fail "page $p returned $code"
    done
  fi
  if [ "$MILESTONE" -ge 8 ]; then
    code=$(curl -s -o /dev/null -w '%{http_code}' "${WEB:-http://localhost:3000}/compare")
    [ "$code" = "200" ] || fail "page /compare returned $code"
  fi

  say "11. the database contains real work"
  [ "$(run_sql 'select count(*) from agents')" -ge 1000 ] || fail "under 1000 agents indexed"
  [ "$(run_sql 'select count(*) from feedback')" -ge 100 ] || fail "under 100 feedback rows"
  if [ "$MILESTONE" -ge 2 ]; then
    [ "$(run_sql 'select count(*) from probe_results')" -ge 5000 ] || fail "under 5000 probes recorded"
    [ "$(run_sql 'select count(*) from (select agent_id from probe_results group by agent_id having count(*) >= 24) t')" -ge 200 ] \
      || fail "fewer than 200 agents with 24 or more probes"
  fi
  if [ "$MILESTONE" -ge 5 ]; then
    [ "$(run_sql 'select count(*) from agent_scores where feedback_total > feedback_kept')" -ge 1 ] \
      || fail "no agent shows feedback_total greater than feedback_kept, the filter never fired"
  fi
else
  say "10-11. runtime checks begin at M1 (current milestone: $MILESTONE)"
fi

say "12. deployed addresses are real and verified"
if [ -f docs/ADDRESSES.md ]; then
  bash scripts/check_addresses.sh
else
  echo "no deployments yet, address check begins when docs/ADDRESSES.md exists"
fi

echo
echo "GATE PASS"

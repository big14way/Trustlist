#!/usr/bin/env bash
# Every address in docs/ADDRESSES.md must be real on the chain it claims.
#
# An address in a submission document that turns out to be wrong is worse
# than no document, so this reads the table back and calls the chain for each
# row. Rows marked "not deployed" are checked the other way round: they must
# have no bytecode, so the document cannot quietly go stale after a deploy.
set -uo pipefail
cd "$(dirname "$0")/.."

DOC=docs/ADDRESSES.md
[ -f "$DOC" ] || { echo "$DOC is missing"; exit 1; }

MAINNET_RPC="${ADDRESS_CHECK_RPC:-https://bsc-rpc.publicnode.com}"

FAIL=0
CHECKED=0

# Table rows look like: | Name | 0xabc... | deployed | note |
# Anything without an address in the second column is prose, not a claim.
while IFS='|' read -r _lead name addr state _rest; do
  name=$(echo "$name" | sed 's/^ *//;s/ *$//;s/`//g')
  addr=$(echo "$addr" | sed 's/^ *//;s/ *$//;s/`//g')
  state=$(echo "$state" | sed 's/^ *//;s/ *$//' | tr '[:upper:]' '[:lower:]')

  case "$addr" in
    0x[0-9a-fA-F]*) ;;
    *) continue ;;
  esac
  [ ${#addr} -eq 42 ] || continue

  SIZE=$(cast codesize "$addr" --rpc-url "$MAINNET_RPC" 2>/dev/null | tail -1)
  CHECKED=$((CHECKED + 1))

  if [ -z "$SIZE" ]; then
    echo "  could not read $name ($addr), rpc failed"
    FAIL=1
    continue
  fi

  case "$state" in
    *"not deployed"*)
      if [ "$SIZE" = "0" ]; then
        echo "  ok       $name is correctly listed as not deployed"
      else
        echo "  STALE    $name has $SIZE bytes of code but the doc says not deployed"
        FAIL=1
      fi
      ;;
    *)
      if [ "$SIZE" != "0" ] && [ "$SIZE" -gt 0 ] 2>/dev/null; then
        echo "  ok       $name $addr ($SIZE bytes)"
      else
        echo "  MISSING  $name $addr has no bytecode on this chain"
        FAIL=1
      fi
      ;;
  esac
done < "$DOC"

echo "  checked $CHECKED addresses against $MAINNET_RPC"
[ "$FAIL" -eq 0 ]

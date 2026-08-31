#!/usr/bin/env bash
# Send a transaction and get its receipt, without letting a flaky receipt
# read look like a failed transaction.
#
# This has now bitten three times on BSC public endpoints, twice in a way
# that could have cost real money. The deploy printed "Some transactions were
# discarded by the RPC node" with the contracts already on chain. The job
# delivery reported nothing at all while the kernel had recorded the
# submission. In both cases the transaction was mined and the tool said
# otherwise, because it treats "I could not read the receipt" and "it did not
# happen" as the same event. They are not, and the difference is the
# difference between retrying safely and paying twice.
#
# So: broadcast, keep the hash whatever happens next, then poll for the
# receipt separately. If the receipt never arrives the hash is still printed,
# because a hash you can look up is recoverable and a lost hash is not.
#
# Usage:
#   source scripts/chainlib.sh
#   send_and_wait "$RPC" "$KEY" <cast send args...>
# Sets: TX_HASH, TX_BLOCK, TX_GAS_USED, TX_STATUS
# Returns 0 when mined and successful, 1 when reverted, 2 when the receipt
# could not be read (and TX_HASH is still set).

send_and_wait() {
  local rpc=$1 key=$2
  shift 2
  TX_HASH=""; TX_BLOCK=""; TX_GAS_USED=""; TX_STATUS=""

  # --async returns as soon as the node accepts the transaction, so the hash
  # exists before anything can go wrong reading it back.
  TX_HASH=$(cast send "$@" --private-key "$key" --rpc-url "$rpc" --async 2>/dev/null) || {
    echo "  the node refused the transaction, nothing was broadcast" >&2
    return 1
  }
  case "$TX_HASH" in
    0x????????????????????????????????????????????????????????????????) ;;
    *) echo "  broadcast produced no usable hash: ${TX_HASH:-empty}" >&2; return 1 ;;
  esac
  echo "  sent $TX_HASH"

  local raw=""
  local i
  for i in $(seq 1 60); do
    raw=$(cast receipt "$TX_HASH" --rpc-url "$rpc" --json 2>/dev/null) && [ -n "$raw" ] && break
    raw=""
    sleep 3
  done

  if [ -z "$raw" ]; then
    echo "  the transaction was broadcast but its receipt could not be read." >&2
    echo "  It may well have succeeded. Check before resending:" >&2
    echo "    cast receipt $TX_HASH --rpc-url <another rpc>" >&2
    echo "    https://bscscan.com/tx/$TX_HASH" >&2
    return 2
  fi

  read -r TX_STATUS TX_BLOCK TX_GAS_USED < <(python3 - "$raw" <<'PY'
import json, sys
r = json.loads(sys.argv[1])
print(int(str(r["status"]), 16), int(str(r["blockNumber"]), 16), int(str(r["gasUsed"]), 16))
PY
  )
  [ "$TX_STATUS" = "1" ] || { echo "  the transaction reverted: $TX_HASH" >&2; return 1; }
  return 0
}

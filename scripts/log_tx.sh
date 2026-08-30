#!/usr/bin/env bash
# Append one mainnet transaction to scripts/tx_log.md.
#
# SPEC.md Section 21 asks for a running log from M4 onwards. Keeping it here,
# written by the scripts that actually send, means the log cannot drift from
# what happened: a transaction that was sent is a transaction that was
# recorded, in the same command.
#
# Mainnet only. A dev chain hash means nothing to a reader and would make the
# log look padded, so callers only invoke this for chain 56.
#
# Usage: scripts/log_tx.sh <what> <tx_hash> <block> <gas_used>
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -eq 4 ] || { echo "usage: $0 <what> <tx_hash> <block> <gas_used>" >&2; exit 1; }
WHAT=$1; TX=$2; BLOCK=$3; GAS=$4

LOG=scripts/tx_log.md
if [ ! -f "$LOG" ]; then
  cat > "$LOG" <<'HEADER'
# Mainnet transaction log

Every transaction TrustList has sent on BSC mainnet, in the order it was
sent. Written by the scripts that send them, not by hand.

| when (UTC) | what | gas | transaction |
|---|---|---|---|
HEADER
fi

printf '| %s | %s | %s | [%s](https://bscscan.com/tx/%s) |\n' \
  "$(date -u '+%Y-%m-%d %H:%M')" "$WHAT" "$GAS" "${TX:0:10}..${TX: -8}" "$TX" >> "$LOG"

echo "  logged    $LOG (block $BLOCK)"

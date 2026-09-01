#!/usr/bin/env bash
# Move gas to the Altana passkey wallet so a session can be granted and revoked.
#
# The Altana relay takes its fee in native BNB, so this wallet has to hold gas
# before either call will go through. The wallet is the one in
# .altana-wallet.json, which scripts/altana_wallet.mjs proved it can restore,
# so anything left here after the revoke is recoverable rather than stranded.
#
# Sizing, at the 0.05 gwei BSC has been charging:
#   grant   665,858 gas  measured on a previous run   0.0000333 BNB
#   revoke  not measured, budgeted at 500,000 gas     0.0000250 BNB
#   margin  in case revoke costs more than budgeted
# 0.00008 BNB covers all three. The deployer keeps the remainder so it can
# still send a top up if the revoke turns out to be dearer than expected.
#
# Usage: bash scripts/fund_altana.sh [--amount-wei N] [--yes]
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck disable=SC1091
source scripts/env.sh
# shellcheck disable=SC1091
source scripts/chainlib.sh
load_env_files

DEST=0xe2C696FE5Cd4187180Cab9F9db9D15e1f1C5Df4b
AMOUNT_WEI=80000000000000
ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --amount-wei) AMOUNT_WEI=$2; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done

RPC="${BSC_RPC_HTTP:?}"
KEY="${DEPLOYER_KEY:?}"
ME=$(cast wallet address --private-key "$KEY")

# The wallet we are funding must be the one we can restore. Funding an
# address that is not in the saved file is how money gets stranded.
SAVED=$(python3 -c "import json;print(json.load(open('.altana-wallet.json'))['address'])")
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
if [ "$(lower "$SAVED")" != "$(lower "$DEST")" ]; then
  echo "refusing: .altana-wallet.json holds $SAVED, not $DEST" >&2
  exit 1
fi

echo "from   $ME"
echo "to     $DEST  (restorable from .altana-wallet.json)"
echo "amount $(cast to-unit "$AMOUNT_WEI" ether) BNB"
echo "gas    $(cast gas-price --rpc-url "$RPC") wei"
echo "before deployer $(cast to-unit "$(cast balance "$ME" --rpc-url "$RPC")" ether) BNB"

if [ "$ASSUME_YES" != "1" ]; then
  printf '\nSend this on mainnet? [y/N] '
  read -r a
  case "$a" in y|Y|yes|YES) ;; *) echo "nothing was sent"; exit 1 ;; esac
fi

set +e
send_and_wait "$RPC" "$KEY" "$DEST" --value "$AMOUNT_WEI"
rc=$?
set -e

echo
case "$rc" in
  0) echo "sent, mined: $TX_HASH" ;;
  2) echo "broadcast but the receipt could not be read: $TX_HASH"
     echo "check https://bscscan.com/tx/$TX_HASH before running this again" ;;
  *) echo "refused or reverted${TX_HASH:+: $TX_HASH}" ;;
esac

echo "after deployer $(cast to-unit "$(cast balance "$ME" --rpc-url "$RPC")" ether) BNB"
echo "after altana   $(cast to-unit "$(cast balance "$DEST" --rpc-url "$RPC")" ether) BNB"
exit "$rc"

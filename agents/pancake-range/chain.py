"""The chain reads the range keeper needs.

PancakeSwap Infinity has no subgraph, so positions are read straight from
the contracts. Addresses were verified on BSC mainnet rather than copied
from a page: the position manager below answers name() with
"Pancake V3 Positions NFT-V1" and has close to five million positions minted.
"""

from __future__ import annotations

import json
import os
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

# Verified on BSC mainnet, see docs/VERIFICATION.md.
POSITION_MANAGER = "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364"
V3_FACTORY = "0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865"

USER_AGENT = "TrustList-RangeKeeper/0.1 (+https://github.com/big14way/Trustlist)"

# Fee tier to tick spacing, as PancakeSwap V3 deploys them.
TICK_SPACING = {100: 1, 500: 10, 2500: 50, 10000: 200}


class ChainError(RuntimeError):
    pass


def _rpc(url: str, method: str, params: List[Any]) -> Any:
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json", "User-Agent": USER_AGENT}
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            out = json.loads(r.read())
    except Exception as e:
        raise ChainError(f"rpc unreachable: {type(e).__name__}") from e
    if "error" in out:
        raise ChainError(out["error"].get("message", "rpc error"))
    return out["result"]


def _call(url: str, to: str, data: str) -> str:
    return _rpc(url, "eth_call", [{"to": to, "data": data}, "latest"])


# Pinned function selectors, each the first four bytes of the keccak hash of
# its signature. They are constants rather than computed because Python has
# no keccak in the standard library, and this agent is deliberately
# dependency free. Verified against live calls on BSC mainnet.
SEL_POSITIONS = "0x99fbab88"       # positions(uint256)
SEL_GET_POOL = "0x1698ee82"        # getPool(address,address,uint24)
SEL_SLOT0 = "0x3850c7bd"           # slot0()
SEL_DECIMALS = "0x313ce567"        # decimals()
SEL_SYMBOL = "0x95d89b41"          # symbol()


def _u256(v: int) -> str:
    return f"{v:064x}"


def _addr_arg(a: str) -> str:
    return f"{int(a, 16):064x}"


def _word(data: str, i: int) -> int:
    start = 2 + i * 64
    return int(data[start : start + 64], 16)


def _signed(value: int, bits: int) -> int:
    """Two's complement, for the int24 ticks the pool returns."""
    if value >= 1 << (bits - 1):
        return value - (1 << bits)
    return value


def read_position(url: str, token_id: int) -> Dict[str, Any]:
    data = _call(url, POSITION_MANAGER, SEL_POSITIONS + _u256(token_id))
    if len(data) < 2 + 12 * 64:
        raise ChainError("position manager returned an unexpected result")
    return {
        "token0": f"0x{data[2 + 2 * 64 + 24 : 2 + 3 * 64]}",
        "token1": f"0x{data[2 + 3 * 64 + 24 : 2 + 4 * 64]}",
        "fee": _word(data, 4),
        "tick_lower": _signed(_word(data, 5), 24),
        "tick_upper": _signed(_word(data, 6), 24),
        "liquidity": _word(data, 7),
        "tokens_owed0": _word(data, 10),
        "tokens_owed1": _word(data, 11),
    }


def read_pool(url: str, token0: str, token1: str, fee: int) -> str:
    data = _call(url, V3_FACTORY, SEL_GET_POOL + _addr_arg(token0) + _addr_arg(token1) + _u256(fee))
    pool = f"0x{data[26:66]}"
    if int(pool, 16) == 0:
        raise ChainError("no pool exists for that pair and fee tier")
    return pool


def read_current_tick(url: str, pool: str) -> int:
    data = _call(url, pool, SEL_SLOT0)
    # slot0 returns sqrtPriceX96, tick, ... ; the tick is the second word.
    return _signed(_word(data, 1), 24)


def read_token_meta(url: str, token: str) -> Tuple[int, str]:
    try:
        dec = int(_call(url, token, SEL_DECIMALS), 16)
    except ChainError:
        dec = 18
    try:
        raw = _call(url, token, SEL_SYMBOL)
        # Dynamic string: offset, length, then the bytes.
        length = _word(raw, 1)
        text = bytes.fromhex(raw[2 + 2 * 64 : 2 + 2 * 64 + length * 2]).decode("utf-8", "replace")
        symbol = text.strip() or token[:8]
    except Exception:
        symbol = token[:8]
    return dec, symbol

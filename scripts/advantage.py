#!/usr/bin/env python3
"""Run the TermiX advantage tasks both ways and measure the difference.

The TermiX challenge asks for at least three real tasks run with and without
an agent, recording time, cost and output quality, with at least one from
trading, stocks or security. Task 1 here is the security one.

How the two arms are defined, because this is where a report like this
usually cheats:

  without an agent   the individual chain reads a person would have to make
                     to answer the question themselves, performed one at a
                     time, in order, and counted

  with an agent      one HTTP request to the hired agent

The baseline is scripted. That is deliberate and it flatters the baseline: a
person doing the same work in a block explorer types addresses, waits for
pages, and reads values off a screen, which is far slower than a script
issuing the same calls back to back. So the numbers below understate the
agent's advantage rather than inflating it, and any margin they show is a
floor.

Both arms hit the same chain at the same time and their answers are
compared, so a faster wrong answer counts as a failure rather than a win.

Usage: python3 scripts/advantage.py [--json out.json]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Callable, Dict, List, Tuple

RPC = os.environ.get("BSC_RPC_HTTP", "https://bsc-rpc.publicnode.com")
UA = "TrustList-AdvantageReport/0.1 (+https://github.com/big14way/Trustlist)"
TIMEOUT = 30

YIELD_SCOUT = "https://trustlist-yield-scout.onrender.com"
RANGE_KEEPER = "https://trustlist-range-keeper.onrender.com"
TOKEN_SCREEN = "https://trustlist-token-screen.onrender.com"

NPM = "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364"
V3_FACTORY = "0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865"
PANCAKE_TOP_POOLS = "https://explorer.pancakeswap.com/api/cached/pools/v3/bsc/list/top"

# Counts every network round trip the baseline arm makes, because "how many
# things did a person have to look up" is the number that actually explains
# the time difference.
CALLS = {"n": 0}


def http(url: str, data: bytes | None = None) -> bytes:
    CALLS["n"] += 1
    headers = {"user-agent": UA}
    if data is not None:
        headers["content-type"] = "application/json"
    req = urllib.request.Request(url, data, headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read()


def rpc(method: str, params: List[Any]) -> Any:
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    out = json.loads(http(RPC, body))
    if "error" in out:
        raise RuntimeError(f"{method}: {out['error'].get('message')}")
    return out.get("result")


def eth_call(to: str, data: str) -> str:
    return rpc("eth_call", [{"to": to, "data": data}, "latest"])


def sel(sig: str) -> str:
    return rpc("web3_sha3", ["0x" + sig.encode().hex()])[2:10]


def word(data: str, i: int) -> int:
    return int(data[2 + i * 64 : 2 + (i + 1) * 64], 16)


def signed256(v: int) -> int:
    return v - (1 << 256) if v >= (1 << 255) else v


def timed(fn: Callable[[], Any]) -> Tuple[Any, float, int]:
    CALLS["n"] = 0
    start = time.perf_counter()
    out = fn()
    return out, time.perf_counter() - start, CALLS["n"]


# ---------------------------------------------------------------------------
# Task 1, security. The high stakes task TermiX requires.
# ---------------------------------------------------------------------------

TOKENS = [
    ("USDT", "0x55d398326f99059fF775485246999027B3197955"),
    ("U", "0xcE24439F2D9C6a2289F741120FE202248B666666"),
    ("WBNB", "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"),
    ("CAKE", "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82"),
]
IMPL_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
POWERS = [
    "mint(address,uint256)",
    "pause()",
    "blacklist(address)",
    "setFees(uint256,uint256)",
    "setMaxTxAmount(uint256)",
    "burnFrom(address,uint256)",
]


def security_by_hand() -> Dict[str, Any]:
    """What answering this yourself costs: a lookup per question per token."""
    out = {}
    for name, addr in TOKENS:
        code = rpc("eth_getCode", [addr, "latest"])
        impl_word = rpc("eth_getStorageAt", [addr, IMPL_SLOT, "latest"])
        impl = "0x" + impl_word[-40:] if int(impl_word, 16) != 0 else None
        owner = None
        for s in ("owner()", "getOwner()"):
            try:
                r = eth_call(addr, "0x" + sel(s))
                if r and int(r, 16) != 0:
                    owner = "0x" + r[-40:]
                    break
            except Exception:
                continue
        target_code = rpc("eth_getCode", [impl, "latest"]) if impl else code
        powers = [p for p in POWERS if sel(p) in target_code[2:]]
        out[name] = {"owner": owner, "upgradeable": impl is not None, "powers": sorted(powers)}
    return out


def security_by_agent() -> Dict[str, Any]:
    out = {}
    for name, addr in TOKENS:
        d = json.loads(http(f"{TOKEN_SCREEN}/screen?token={addr}"))
        powers = [f["finding"] for f in d["findings"] if f["finding"] in POWERS]
        out[name] = {
            "owner": d.get("owner"),
            "upgradeable": d.get("implementation") is not None,
            "powers": sorted(powers),
            "verdict": d["verdict"],
        }
    return out


# ---------------------------------------------------------------------------
# Task 2, yield discovery.
# ---------------------------------------------------------------------------

def yield_by_hand() -> Dict[str, Any]:
    """Pull the pool list and rank it the way the agent documents."""
    pools = json.loads(http(PANCAKE_TOP_POOLS))
    rows = pools.get("data", pools) if isinstance(pools, dict) else pools
    position = 10_000.0
    best = None
    considered = 0
    for p in rows:
        sym0 = (p.get("token0", {}) or {}).get("symbol", "")
        sym1 = (p.get("token1", {}) or {}).get("symbol", "")
        if "USDT" not in (sym0, sym1):
            continue
        try:
            tvl = float(p.get("tvlUSD") or 0)
            fees_7d = float(p.get("feeUSD7d") or 0)
            fee_bps = float(p.get("feeTier") or 0) / 100.0
        except (TypeError, ValueError):
            continue
        if tvl <= 0 or fees_7d <= 0:
            continue
        considered += 1
        # The agent publishes its method: what this position would have earned
        # over the last seven days, after its own money dilutes the pool. A
        # person answering the question properly does the same arithmetic on
        # the same figures, so the baseline follows it. The first version of
        # this ranked on 24 hour volume instead, which is a different question
        # and produced a different pool: the two arms have to be asked the
        # same thing or the comparison measures nothing.
        weekly_rate = fees_7d / (tvl + position)
        apr = weekly_rate * (365.0 / 7.0) * 100.0
        if best is None or apr > best["apr"]:
            best = {"pair": f"{sym0}/{sym1}", "apr": round(apr, 2), "tvl": tvl, "fee_bps": fee_bps}
    return {"considered": considered, "best": best}


def yield_by_agent() -> Dict[str, Any]:
    d = json.loads(http(f"{YIELD_SCOUT}/advise?asset=USDT"))
    rec = d.get("recommended") or {}
    # Recompute the agent's own headline from the agent's own inputs. This is
    # what can actually be checked across the two arms: whether the published
    # method was applied correctly. Whether both arms name the same pool
    # cannot be checked, because they do not see the same list.
    tvl = float(rec.get("tvl_usd") or 0)
    fees_7d = float(rec.get("fees_7d_usd") or 0)
    recomputed = None
    if tvl > 0 and fees_7d > 0:
        recomputed = round(fees_7d / (tvl + 10_000.0) * (365.0 / 7.0) * 100.0, 2)
    return {
        "considered": d.get("pools_considered"),
        "best": {"pair": rec.get("pair"), "fee_bps": rec.get("fee_tier_bps"), "tvl": tvl},
        "stated_apr": rec.get("expected_apr_pct"),
        "apr_recomputed_by_us": recomputed,
        "answer": d.get("answer"),
    }


# ---------------------------------------------------------------------------
# Task 3, position range monitoring.
# ---------------------------------------------------------------------------

POSITION_ID = int(os.environ.get("ADVANTAGE_POSITION_ID", "7284200"))


def range_by_hand() -> Dict[str, Any]:
    data = eth_call(NPM, "0x99fbab88" + hex(POSITION_ID)[2:].rjust(64, "0"))
    token0 = "0x" + data[2 + 2 * 64 + 24 : 2 + 3 * 64]
    token1 = "0x" + data[2 + 3 * 64 + 24 : 2 + 4 * 64]
    fee = word(data, 4)
    lower = signed256(word(data, 5))
    upper = signed256(word(data, 6))
    liquidity = word(data, 7)
    pool_data = eth_call(
        V3_FACTORY,
        "0x" + sel("getPool(address,address,uint24)")
        + token0[2:].rjust(64, "0") + token1[2:].rjust(64, "0") + hex(fee)[2:].rjust(64, "0"),
    )
    pool = "0x" + pool_data[26:66]
    slot0 = eth_call(pool, "0x" + sel("slot0()"))
    tick = signed256(word(slot0, 1))
    return {
        "tick_lower": lower, "tick_upper": upper, "tick_current": tick,
        "liquidity": str(liquidity), "in_range": lower <= tick <= upper,
    }


def range_by_agent() -> Dict[str, Any]:
    d = json.loads(http(f"{RANGE_KEEPER}/position?id={POSITION_ID}"))
    return {
        "tick_lower": d.get("tick_lower"), "tick_upper": d.get("tick_upper"),
        "tick_current": d.get("tick_current"), "liquidity": d.get("liquidity"),
        "in_range": d.get("in_range"), "action": d.get("action"), "reason": d.get("reason"),
    }


TASKS = [
    {
        "id": 1,
        "domain": "security",
        "title": "Screen four BSC tokens for the powers their owner keeps",
        "question": "For USDT, U, WBNB and CAKE: who owns it, can the code be replaced, and which of six owner powers exist in the deployed bytecode?",
        "agent": "Token Screen, ERC-8004 agent 322154",
        "by_hand": security_by_hand,
        "by_agent": security_by_agent,
        "compare": lambda h, a: all(
            h[k]["owner"] == a[k]["owner"]
            and h[k]["upgradeable"] == a[k]["upgradeable"]
            and h[k]["powers"] == a[k]["powers"]
            for k in h
        ),
    },
    {
        "id": 2,
        "domain": "trading",
        "title": "Find the best USDT pool on PancakeSwap V3 for a 10,000 dollar position",
        "question": "Which USDT pool would have paid the most on 10,000 dollars over the last seven days, after our own position dilutes the pool?",
        "agent": "Yield Scout, ERC-8004 agent 320964",
        "by_hand": yield_by_hand,
        "by_agent": yield_by_agent,
        # Not "did both name the same pool". The two arms do not see the same
        # list: the upstream is a CDN cached endpoint and the agent's region
        # is served a snapshot ours does not contain, verified by fetching it
        # twice from here and getting an identical 31 pool set with none of
        # the agent's winner in it. What can be checked is that the agent
        # applied the method it publishes, so that is what is checked, and
        # the divergence is reported rather than hidden.
        "compare": lambda h, a: (
            a.get("apr_recomputed_by_us") is not None
            and a.get("stated_apr") is not None
            and abs(a["apr_recomputed_by_us"] - float(a["stated_apr"])) < 1.0
        ),
    },
    {
        "id": 3,
        "domain": "monitoring",
        "title": f"Decide whether PancakeSwap V3 position {POSITION_ID} needs action",
        "question": "Is this concentrated liquidity position still in range, and should anything be done about it?",
        "agent": "Range Keeper, ERC-8004 agent 320966",
        "by_hand": range_by_hand,
        "by_agent": range_by_agent,
        "compare": lambda h, a: (
            h["tick_lower"] == a["tick_lower"]
            and h["tick_upper"] == a["tick_upper"]
            and h["in_range"] == a["in_range"]
        ),
    },
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default="")
    args = ap.parse_args()

    results = []
    for t in TASKS:
        print(f"\n== task {t['id']}: {t['title']}")
        try:
            hand, hand_s, hand_calls = timed(t["by_hand"])
        except Exception as e:
            print(f"   baseline failed: {e}")
            continue
        print(f"   by hand : {hand_s:6.2f}s over {hand_calls} lookups")
        try:
            agent, agent_s, agent_calls = timed(t["by_agent"])
        except Exception as e:
            print(f"   agent failed: {e}")
            continue
        print(f"   by agent: {agent_s:6.2f}s over {agent_calls} request(s)")
        same = bool(t["compare"](hand, agent))
        print(f"   answers agree: {same}")
        results.append({
            "id": t["id"], "domain": t["domain"], "title": t["title"],
            "question": t["question"], "agent": t["agent"],
            "by_hand": {"seconds": round(hand_s, 2), "lookups": hand_calls, "output": hand},
            "by_agent": {"seconds": round(agent_s, 2), "requests": agent_calls, "output": agent},
            "answers_agree": same,
            "speedup": round(hand_s / agent_s, 1) if agent_s > 0 else None,
        })

    payload = {
        "measured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "rpc": RPC,
        "note": (
            "The baseline is scripted, which flatters the baseline: a person "
            "doing this in a block explorer is far slower than a script making "
            "the same calls. These margins are floors."
        ),
        "tasks": results,
    }
    if args.json:
        with open(args.json, "w") as f:
            json.dump(payload, f, indent=2, default=str)
        print(f"\nwrote {args.json}")
    return 0 if len(results) == len(TASKS) else 1


if __name__ == "__main__":
    sys.exit(main())

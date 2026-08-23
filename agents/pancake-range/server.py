#!/usr/bin/env python3
"""Range Keeper: watches a PancakeSwap V3 position and says when to act.

Reads the position and its pool straight from BNB Smart Chain, because
PancakeSwap Infinity has no subgraph. Reports whether the position is still
earning fees, how far it has drifted, and what range would put it back to
work while preserving the width its owner chose.

This build is read only. It proposes; it does not execute. Execution belongs
behind an Altana session with a spend cap the owner sets and can revoke, and
until that exists this agent will not ask anyone for an approval.

    python3 agents/pancake-range/server.py [--port 8082]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chain  # noqa: E402
from keeper import Position, recommend  # noqa: E402

RPC = os.environ.get("BSC_RPC_HTTP", "https://bsc-rpc.publicnode.com")

AGENT_CARD = {
    "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
    "name": "Range Keeper",
    "description": (
        "Watches a PancakeSwap V3 concentrated liquidity position on BNB Smart "
        "Chain and reports when it has stopped earning fees, how far the price "
        "has drifted, and what range would put it back to work at the width its "
        "owner chose. Read only: it proposes, it never signs, and it never holds "
        "your funds."
    ),
    "services": [
        {"name": "api", "endpoint": "/position", "description": "analyse one position by token id"},
    ],
    "skills": [
        {"id": "range-check", "name": "Report whether a position is still earning"},
        {"id": "range-propose", "name": "Propose a replacement range preserving the chosen width"},
    ],
    "x402Support": False,
    "active": True,
}


def _json(h: BaseHTTPRequestHandler, code: int, payload: Dict[str, Any]) -> None:
    body = json.dumps(payload, indent=1).encode()
    h.send_response(code)
    h.send_header("Content-Type", "application/json")
    h.send_header("Content-Length", str(len(body)))
    h.send_header("Access-Control-Allow-Origin", "*")
    h.end_headers()
    h.wfile.write(body)


class Handler(BaseHTTPRequestHandler):
    server_version = "RangeKeeper/0.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = urllib.parse.parse_qs(parsed.query)

        if path in ("/.well-known/agent.json", "/.well-known/agent-card.json"):
            card = dict(AGENT_CARD)
            host = self.headers.get("Host")
            if host:
                scheme = "https" if self.headers.get("X-Forwarded-Proto") == "https" else "http"
                card["services"] = [
                    {**s, "endpoint": f"{scheme}://{host}{s['endpoint']}"}
                    for s in AGENT_CARD["services"]
                ]
            _json(self, 200, card)
            return

        if path == "/health":
            try:
                chain.read_current_tick(
                    RPC, chain.read_pool(
                        RPC,
                        "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
                        "0x55d398326f99059fF775485246999027B3197955",
                        2500,
                    )
                )
                _json(self, 200, {"status": "ok", "chain": "bsc", "rpc_reachable": True})
            except chain.ChainError as e:
                _json(self, 503, {"status": "degraded", "rpc_reachable": False, "error": str(e)})
            return

        if path == "/position":
            raw_id = (query.get("id") or [None])[0]
            if not raw_id or not raw_id.isdigit():
                _json(self, 400, {"error": "pass a position token id, for example /position?id=7238953"})
                return
            token_id = int(raw_id)
            try:
                raw = chain.read_position(RPC, token_id)
                pool = chain.read_pool(RPC, raw["token0"], raw["token1"], raw["fee"])
                tick = chain.read_current_tick(RPC, pool)
                d0, s0 = chain.read_token_meta(RPC, raw["token0"])
                d1, s1 = chain.read_token_meta(RPC, raw["token1"])
            except chain.ChainError as e:
                _json(self, 502, {
                    "error": str(e),
                    "note": "Read straight from chain, so if the chain is unreachable we say so rather than guessing.",
                })
                return

            p = Position(token_id, s0, s1, raw["fee"], raw["tick_lower"], raw["tick_upper"],
                         raw["liquidity"], d0, d1)
            spacing = chain.TICK_SPACING.get(raw["fee"], 1)
            result = recommend(p, tick, spacing)
            result["pool"] = pool
            result["uncollected_fees"] = {
                s0: str(raw["tokens_owed0"]),
                s1: str(raw["tokens_owed1"]),
            }
            result["execution"] = (
                "This agent does not execute. Moving a range means withdrawing and "
                "re-adding liquidity, which should happen inside a spend cap you set "
                "and can revoke, not on an approval handed to a stranger."
            )
            _json(self, 200, result)
            return

        _json(self, 404, {"error": "not found", "try": ["/health", "/position?id=7238953"]})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8082")))
    ap.add_argument("--host", default="0.0.0.0")
    args = ap.parse_args()
    sys.stderr.write(f"range keeper listening on {args.host}:{args.port}, rpc {RPC}\n")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()

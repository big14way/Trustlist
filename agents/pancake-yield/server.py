#!/usr/bin/env python3
"""Yield Scout: a read only PancakeSwap agent.

Serves a ranked view of PancakeSwap V3 pools on BNB Smart Chain, built from
PancakeSwap's own explorer API, with the reasoning shown next to every
answer. It holds no funds, requests no approvals, and signs nothing.

Standard library only, deliberately: an agent that anyone can run without
installing anything is easier to trust and easier to keep alive.

    python3 agents/pancake-yield/server.py [--port 8081]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scout import DEFAULT_POSITION_USD, rank  # noqa: E402

SOURCE = "https://explorer.pancakeswap.com/api/cached/pools/v3/bsc/list/top"
USER_AGENT = "TrustList-YieldScout/0.1 (+https://github.com/big14way/Trustlist)"
# Pool statistics move slowly and the upstream is cached anyway. Refreshing
# more often would add load without adding information.
CACHE_SECONDS = 300


class PoolCache:
    """Holds the last good response and how old it is.

    If upstream fails we report the failure and the age of what we have,
    rather than passing off stale numbers as current.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._pools: Optional[List[Dict[str, Any]]] = None
        self._fetched_at = 0.0
        self._error: Optional[str] = None

    def get(self) -> tuple[Optional[List[Dict[str, Any]]], float, Optional[str]]:
        with self._lock:
            fresh = self._pools is not None and (time.time() - self._fetched_at) < CACHE_SECONDS
            if fresh:
                return self._pools, self._fetched_at, None
        pools, err = self._fetch()
        with self._lock:
            if pools is not None:
                self._pools = pools
                self._fetched_at = time.time()
                self._error = None
            else:
                self._error = err
            return self._pools, self._fetched_at, self._error

    @staticmethod
    def _fetch() -> tuple[Optional[List[Dict[str, Any]]], Optional[str]]:
        req = urllib.request.Request(SOURCE, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                body = json.loads(r.read())
        except urllib.error.HTTPError as e:
            return None, f"pancakeswap explorer returned {e.code}"
        except Exception as e:  # network, dns, tls, malformed json
            return None, f"pancakeswap explorer unreachable: {type(e).__name__}"
        if not isinstance(body, list):
            return None, "pancakeswap explorer returned an unexpected shape"
        return body, None


CACHE = PoolCache()

AGENT_CARD = {
    "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
    "name": "Yield Scout",
    "description": (
        "Reads live PancakeSwap V3 pool data on BNB Smart Chain and reports "
        "better risk adjusted liquidity options for a given asset, with the "
        "reasoning shown. Read only: it holds no funds, requests no approvals, "
        "and signs nothing."
    ),
    "services": [
        {"name": "api", "endpoint": "/pools", "description": "ranked pools with every input visible"},
        {"name": "api", "endpoint": "/advise", "description": "recommendation for one asset"},
    ],
    "skills": [
        {"id": "yield-scan", "name": "Rank PancakeSwap pools by risk adjusted fee return"},
        {"id": "pool-explain", "name": "Explain why a pool is or is not worth entering"},
    ],
    "x402Support": False,
    "active": True,
}


def _json(handler: BaseHTTPRequestHandler, code: int, payload: Dict[str, Any]) -> None:
    body = json.dumps(payload, indent=1).encode()
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.end_headers()
    handler.wfile.write(body)


class Handler(BaseHTTPRequestHandler):
    server_version = "YieldScout/0.1"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = urllib.parse.parse_qs(parsed.query)

        if path in ("/.well-known/agent.json", "/.well-known/agent-card.json"):
            card = dict(AGENT_CARD)
            base = self.headers.get("Host")
            if base:
                scheme = "https" if self.headers.get("X-Forwarded-Proto") == "https" else "http"
                card["services"] = [
                    {**s, "endpoint": f"{scheme}://{base}{s['endpoint']}"}
                    for s in AGENT_CARD["services"]
                ]
            _json(self, 200, card)
            return

        if path == "/health":
            pools, fetched_at, err = CACHE.get()
            _json(
                self,
                200 if pools else 503,
                {
                    "status": "ok" if pools and not err else "degraded",
                    "pools_known": len(pools) if pools else 0,
                    "data_age_seconds": round(time.time() - fetched_at, 1) if fetched_at else None,
                    "upstream_error": err,
                },
            )
            return

        if path in ("/pools", "/advise"):
            asset = (query.get("asset") or [None])[0]
            try:
                position = float((query.get("position") or [DEFAULT_POSITION_USD])[0])
            except ValueError:
                _json(self, 400, {"error": "position must be a number of dollars"})
                return
            if position <= 0 or position > 100_000_000:
                _json(self, 400, {"error": "position must be between 0 and 100,000,000"})
                return
            pools, fetched_at, err = CACHE.get()
            if pools is None:
                _json(
                    self,
                    503,
                    {
                        "error": err or "no pool data",
                        "note": "We would rather answer nothing than answer from stale numbers.",
                        "source": SOURCE,
                    },
                )
                return

            ranked = rank(pools, asset, position)
            payload: Dict[str, Any] = {
                "source": SOURCE,
                "data_age_seconds": round(time.time() - fetched_at, 1),
                "pools_considered": len(pools),
                "asset": asset,
                "position_usd": position,
                "ranked_by": (
                    "what this position size would have earned over the last seven "
                    "days, after its own dilution of the pool"
                ),
            }
            if err:
                payload["warning"] = f"{err}; serving the last good data"

            if path == "/advise":
                if not ranked:
                    payload["answer"] = (
                        f"No PancakeSwap V3 pool in the top set holds {asset}."
                        if asset
                        else "No pool data to advise on."
                    )
                    payload["results"] = []
                    _json(self, 200, payload)
                    return
                best = ranked[0]
                payload["answer"] = best["why"]
                payload["recommended"] = best
                payload["alternatives"] = ranked[1:4]
                payload["caveat"] = (
                    "Fee return is what the pool paid, not what it will pay. "
                    "Concentrated liquidity also carries impermanent loss, which "
                    "this agent does not estimate."
                )
            else:
                payload["results"] = ranked

            _json(self, 200, payload)
            return

        _json(
            self,
            404,
            {
                "error": "not found",
                "try": ["/health", "/pools", "/advise?asset=CAKE&position=25000"],
            },
        )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8081")))
    ap.add_argument("--host", default="0.0.0.0")
    args = ap.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    sys.stderr.write(f"yield scout listening on {args.host}:{args.port}\n")
    server.serve_forever()


if __name__ == "__main__":
    main()

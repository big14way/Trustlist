#!/usr/bin/env python3
"""Token Screen: an ERC-8004 agent that says what a token's owner can do to you.

Read only. It holds no funds, requests no approvals, and signs nothing, so
the worst it can do is be wrong, and every finding names the chain evidence
so being wrong is checkable.

    python3 agents/token-screen/server.py [--port 8083]
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
from screen import RpcError, screen  # noqa: E402

AGENT_CARD = {
    "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
    "name": "Token Screen",
    "description": (
        "Reads a BSC token contract and reports what powers its owner keeps: "
        "upgradeability, mint, pause, blacklist, fee changes. Every finding "
        "cites the storage slot or bytecode selector it came from. Read only: "
        "it holds no funds, requests no approvals, and signs nothing."
    ),
    "services": [
        {"name": "api", "endpoint": "/screen", "description": "screen one token address"},
    ],
    "skills": [
        {"id": "owner-powers", "name": "Report what a token owner can still do to holders"},
        {"id": "upgrade-check", "name": "Detect an upgradeable proxy and name its admin"},
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
    server_version = "TokenScreen/0.1"

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
            _json(self, 200, {"status": "ok", "chain": "bsc"})
            return

        if path == "/screen":
            token = (query.get("token") or [""])[0].strip()
            if not token:
                _json(self, 400, {
                    "error": "give a token address",
                    "try": ["/screen?token=0x55d398326f99059fF775485246999027B3197955"],
                })
                return
            if not (token.startswith("0x") and len(token) == 42):
                _json(self, 400, {"error": "that is not a BSC address", "got": token})
                return
            try:
                int(token, 16)
            except ValueError:
                _json(self, 400, {"error": "that is not a BSC address", "got": token})
                return
            try:
                _json(self, 200, screen(token))
            except RpcError as e:
                # Say which side failed. An agent that reports "no risks
                # found" when it could not read the chain is worse than one
                # that admits it could not look.
                _json(self, 502, {
                    "error": "could not read the chain, so this is not a clean bill of health",
                    "detail": str(e),
                })
            return

        _json(self, 404, {"error": "not found", "try": ["/health", "/screen?token=0x..."]})


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8083")))
    ap.add_argument("--host", default="0.0.0.0")
    args = ap.parse_args()
    sys.stderr.write(f"token screen listening on {args.host}:{args.port}\n")
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Sampled liveness measurement for ERC-8004 agents on BSC mainnet.

Draws a seeded random sample of agent ids, reads tokenURI via eth_call,
fetches the agent card, extracts declared HTTP endpoints, and probes them.
Aliveness rule follows SPEC.md Section 12: 2xx, 3xx, 401, 402, 403 count as
alive; DNS failure, TLS failure, connection refused, timeout, 404, and 5xx
count as down. Private address ranges are never contacted (SSRF guard).
"""
import concurrent.futures as cf
import ipaddress
import json
import random
import re
import socket
import ssl
import sys
import urllib.request
import urllib.error

RPC = "https://bsc-rpc.publicnode.com"
IDENTITY = "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"
LAST_ID = 269234
SAMPLE = 300
SEED = 8004
UA = "TrustList-prober-preview/0.1 (hackathon research; contact: repo owner)"
TIMEOUT = 8

ctx = ssl.create_default_context()

RPC_FALLBACK = "https://bsc-dataseed.bnbchain.org"

def rpc_call(method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    last_exc = None
    for endpoint in (RPC, RPC_FALLBACK):
        for _ in range(2):
            req = urllib.request.Request(
                endpoint, data=body,
                headers={"Content-Type": "application/json", "User-Agent": UA})
            try:
                with urllib.request.urlopen(req, timeout=15) as r:
                    return json.loads(r.read())
            except Exception as e:
                last_exc = e
    raise last_exc

def token_uri(agent_id):
    data = "0xc87b56dd" + hex(agent_id)[2:].rjust(64, "0")
    try:
        res = rpc_call("eth_call", [{"to": IDENTITY, "data": data}, "latest"])
    except Exception:
        return None, "rpc_error"
    if "error" in res:
        return None, "revert"
    raw = res.get("result", "0x")
    if raw in ("0x", None) or len(raw) < 130:
        return None, "empty"
    try:
        b = bytes.fromhex(raw[2:])
        strlen = int.from_bytes(b[32:64], "big")
        s = b[64:64 + strlen].decode("utf-8", "replace").strip()
        return (s, "ok") if s else (None, "empty")
    except Exception:
        return None, "decode_fail"

def is_private_host(host):
    try:
        infos = socket.getaddrinfo(host, None)
    except Exception:
        return None  # dns failure, handled by caller
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved:
            return True
    return False

def fetch(url, method="GET"):
    """Return (status, body_prefix) or (None, failure_kind)."""
    from urllib.parse import urlparse
    p = urlparse(url)
    if p.scheme not in ("http", "https") or not p.hostname:
        return None, "bad_url"
    priv = is_private_host(p.hostname)
    if priv is None:
        return None, "dns"
    if priv:
        return None, "private_blocked"
    req = urllib.request.Request(url, headers={"User-Agent": UA}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as r:
            return r.status, r.read(4096)
    except urllib.error.HTTPError as e:
        return e.code, b""
    except urllib.error.URLError as e:
        reason = str(e.reason).lower()
        if "timed out" in reason:
            return None, "timeout"
        if "ssl" in reason or "certificate" in reason:
            return None, "tls"
        if "refused" in reason:
            return None, "conn_refused"
        return None, "dns" if "resolution" in reason or "nodename" in reason else "conn_error"
    except Exception:
        return None, "conn_error"

def resolve_card(uri):
    """Return (card_bytes or None, classification)."""
    if uri.startswith("data:"):
        import base64
        try:
            meta, payload = uri.split(",", 1)
            raw = base64.b64decode(payload) if ";base64" in meta else payload.encode()
            return raw, "data"
        except Exception:
            return None, "data_bad"
    if uri.startswith("ipfs://"):
        path = uri[len("ipfs://"):]
        for gw in ("https://ipfs.io/ipfs/", "https://dweb.link/ipfs/"):
            status, body = fetch(gw + path)
            if status and 200 <= status < 300:
                return body, "ipfs"
        return None, "ipfs_unreachable"
    if uri.startswith("http://") or uri.startswith("https://"):
        status, body = fetch(uri)
        if status and 200 <= status < 300 and body:
            return body, "https"
        return None, f"http_{status or body}"
    return None, "invalid_scheme"

URL_RE = re.compile(rb'https?://[^\s"\'<>\\]+')

def extract_endpoints(card_bytes):
    urls = []
    try:
        card = json.loads(card_bytes)
    except Exception:
        return urls
    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in ("endpoints", "endpoint", "url", "serviceEndpoint", "service_endpoints", "baseUrl"):
                    walk(v)
                elif isinstance(v, (dict, list)):
                    walk(v)
                elif isinstance(v, str) and v.startswith("http") and k in ("url", "uri", "endpoint", "baseUrl", "serviceEndpoint"):
                    urls.append(v)
        elif isinstance(node, list):
            for item in node:
                walk(item)
        elif isinstance(node, str) and node.startswith("http"):
            urls.append(node)
    walk(card)
    seen, out = set(), []
    for u in urls:
        if u not in seen:
            seen.add(u)
            out.append(u)
    return out[:3]

ALIVE_DOWN_STATUSES = {404}

def endpoint_alive(url):
    status, kind = fetch(url)
    if status is None:
        return False, str(kind)
    if status == 404 or status >= 500:
        return False, f"http_{status}"
    return True, f"http_{status}"

def check_agent(agent_id):
    uri, st = token_uri(agent_id)
    rec = {"id": agent_id, "uri_status": st, "uri": (uri or "")[:120]}
    if not uri:
        rec["result"] = "no_uri"
        return rec
    card, cls = resolve_card(uri)
    rec["card"] = cls
    if card is None:
        rec["result"] = "card_unreachable"
        return rec
    try:
        json.loads(card)
    except Exception:
        rec["result"] = "card_not_json"
        return rec
    eps = extract_endpoints(card)
    rec["endpoints"] = len(eps)
    if not eps:
        rec["result"] = "no_endpoints"
        return rec
    for ep in eps:
        ok, detail = endpoint_alive(ep)
        if ok:
            rec["result"] = "live"
            rec["detail"] = detail
            return rec
    rec["result"] = "endpoints_down"
    rec["detail"] = detail
    return rec

def main():
    random.seed(SEED)
    ids = random.sample(range(1, LAST_ID + 1), SAMPLE)
    results = []
    with cf.ThreadPoolExecutor(max_workers=12) as ex:
        for rec in ex.map(check_agent, ids):
            results.append(rec)
            sys.stderr.write(".")
            sys.stderr.flush()
    sys.stderr.write("\n")
    from collections import Counter
    counts = Counter(r["result"] for r in results)
    live = counts.get("live", 0)
    n = len(results)
    p = live / n
    import math
    se = math.sqrt(p * (1 - p) / n)
    print(json.dumps({
        "sample_size": n,
        "seed": SEED,
        "last_id": LAST_ID,
        "counts": dict(counts),
        "live_pct": round(100 * p, 2),
        "ci95_pct": [round(100 * max(0, p - 1.96 * se), 2), round(100 * (p + 1.96 * se), 2)],
        "card_status": dict(Counter(r.get("card", "none") for r in results)),
        "uri_status": dict(Counter(r["uri_status"] for r in results)),
    }, indent=2))
    with open(sys.argv[1] if len(sys.argv) > 1 else "sample_results.json", "w") as f:
        json.dump(results, f, indent=1)

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""One-off identity registry fastfill via an Alchemy endpoint.

The free tier caps eth_getLogs at 10 blocks on BNB, so range scanning is not
viable there. Instead this enumerates every ERC-721 transfer on the Identity
Registry through alchemy_getAssetTransfers (mints give agent id, owner,
block, tx), batch fetches mint block timestamps, and batch eth_calls
tokenURI(id) for the current URI. Everything written is chain data with a tx
hash or a direct contract read behind it, and audit_data.sh re-derives
samples of it against an independent RPC.

Writes TSV to stdout-adjacent files and loads them with COPY via docker
compose psql. Rows already present in agents (indexed from raw logs) are
left untouched.

Usage: ALCHEMY_URL=... python3 scripts/fastfill_identity.py
"""
import json
import os
import subprocess
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ALCHEMY_URL = os.environ["ALCHEMY_URL"]
IDENTITY = "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"
OUT_DIR = os.path.dirname(os.path.abspath(__file__))
TOKENURI_SELECTOR = "0xc87b56dd"


def rpc(payload, retries=9):
    body = json.dumps(payload).encode()
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                ALCHEMY_URL, data=body, headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            if attempt == retries - 1:
                raise
            if e.code == 429:
                retry_after = e.headers.get("Retry-After")
                wait = float(retry_after) if retry_after else min(2 ** attempt, 30)
                time.sleep(wait + 1)
            else:
                time.sleep(min(2 ** attempt, 30))
        except Exception:
            if attempt == retries - 1:
                raise
            time.sleep(min(2 ** attempt, 30))
    return None


def page_transfers():
    """Yield every ERC-721 transfer on the registry, ascending."""
    page_key = None
    page = 0
    while True:
        params = {
            "fromBlock": "0x0",
            "toBlock": "latest",
            "contractAddresses": [IDENTITY],
            "category": ["erc721"],
            "maxCount": "0x3e8",
            "order": "asc",
        }
        if page_key:
            params["pageKey"] = page_key
        res = rpc({"jsonrpc": "2.0", "id": 1, "method": "alchemy_getAssetTransfers", "params": [params]})
        if "error" in res:
            raise RuntimeError(res["error"])
        result = res["result"]
        yield from result.get("transfers", [])
        page += 1
        if page % 25 == 0:
            print(f"  page {page}", file=sys.stderr)
        page_key = result.get("pageKey")
        if not page_key:
            return
        time.sleep(0.35)


def batch_rpc(calls, batch_size=20, workers=2):
    """calls: list of (id_key, method, params). Returns {id_key: result}."""
    groups = [calls[i : i + batch_size] for i in range(0, len(calls), batch_size)]
    out = {}

    def run(group):
        payload = [
            {"jsonrpc": "2.0", "id": i, "method": m, "params": p}
            for i, (_, m, p) in enumerate(group)
        ]
        res = rpc(payload)
        results = {}
        for item in res:
            key = group[item["id"]][0]
            results[key] = item.get("result")
        time.sleep(0.3)
        return results

    done = 0
    with ThreadPoolExecutor(max_workers=workers) as ex:
        for results in ex.map(run, groups):
            out.update(results)
            done += 1
            if done % 200 == 0:
                print(f"  batch {done}/{len(groups)}", file=sys.stderr)
    return out


def existing_agent_ids():
    r = subprocess.run(
        ["docker", "compose", "exec", "-T", "db", "psql", "-U", "trustlist", "-d", "trustlist",
         "-tAc", "select agent_id::text from agents"],
        capture_output=True, text=True, check=True,
        cwd=os.path.join(OUT_DIR, ".."),
    )
    return set(line.strip() for line in r.stdout.splitlines() if line.strip())


def main():
    print("phase A: paging all transfers", file=sys.stderr)
    agents = {}  # id -> [owner, block, tx]
    for t in page_transfers():
        token_id = int(t["tokenId"], 16)
        block = int(t["blockNum"], 16)
        if t["from"] == "0x0000000000000000000000000000000000000000":
            agents[token_id] = [t["to"], block, t["hash"]]
        elif token_id in agents:
            agents[token_id][0] = t["to"]
    print(f"  {len(agents)} agents from transfers", file=sys.stderr)

    known = existing_agent_ids()
    new_ids = [i for i in agents if str(i) not in known]
    print(f"  {len(new_ids)} not yet in database", file=sys.stderr)
    if not new_ids:
        return

    print("phase B: mint block timestamps", file=sys.stderr)
    blocks = sorted({agents[i][1] for i in new_ids})
    block_res = batch_rpc(
        [(b, "eth_getBlockByNumber", [hex(b), False]) for b in blocks]
    )
    block_time = {}
    for b in blocks:
        r = block_res.get(b)
        if r and r.get("timestamp"):
            block_time[b] = int(r["timestamp"], 16)
    print(f"  {len(block_time)}/{len(blocks)} timestamps", file=sys.stderr)

    print("phase C: tokenURI eth_calls", file=sys.stderr)
    uri_res = batch_rpc(
        [
            (i, "eth_call", [{"to": IDENTITY, "data": TOKENURI_SELECTOR + hex(i)[2:].rjust(64, "0")}, "latest"])
            for i in new_ids
        ]
    )

    def decode_uri(raw):
        if not raw or raw == "0x" or len(raw) < 130:
            return None
        try:
            b = bytes.fromhex(raw[2:])
            strlen = int.from_bytes(b[32:64], "big")
            return b[64 : 64 + strlen].decode("utf-8", "replace")
        except Exception:
            return None

    print("phase D: writing tsv and loading", file=sys.stderr)
    tsv_path = os.path.join(OUT_DIR, "fastfill_agents.tsv")
    skipped = 0
    with open(tsv_path, "w") as f:
        for i in new_ids:
            owner, block, _tx = agents[i]
            ts = block_time.get(block)
            if ts is None:
                skipped += 1
                continue
            uri = decode_uri(uri_res.get(i)) or ""
            uri = uri.replace("\\", "\\\\").replace("\t", " ").replace("\n", " ")
            f.write(f"{i}\t{owner[2:]}\t{uri}\t{block}\t{ts}\n")
    print(f"  wrote {tsv_path}, skipped {skipped} without timestamps", file=sys.stderr)

    root = os.path.join(OUT_DIR, "..")

    def psql(*args, **kw):
        subprocess.run(
            ["docker", "compose", "exec", "-T", "db", "psql", "-U", "trustlist",
             "-d", "trustlist", "-v", "ON_ERROR_STOP=1", *args],
            check=True, cwd=root, **kw,
        )

    psql("-c", "drop table if exists fastfill_stage; "
         "create table fastfill_stage (agent_id numeric, owner_hex text, token_uri text, block bigint, ts bigint)")
    with open(tsv_path) as f:
        psql("-c", "\\copy fastfill_stage from pstdin", stdin=f)
    psql("-c",
         "insert into agents (agent_id, owner, token_uri, registered_block, registered_at, last_seen_block) "
         "select agent_id, decode(owner_hex,'hex'), nullif(token_uri,''), block, to_timestamp(ts), block "
         "from fastfill_stage on conflict (agent_id) do nothing; "
         "drop table fastfill_stage")
    print("done", file=sys.stderr)


if __name__ == "__main__":
    main()

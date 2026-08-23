#!/usr/bin/env python3
"""Trace the first inbound funding transfer for every address that has ever
left feedback, and store it for the trust engine.

Reviewer independence is the whole product claim, and the cleanest evidence
that two reviewers are one operator is that the same wallet paid for both of
their gas. This walks each reviewer's earliest incoming native and token
transfers through alchemy_getAssetTransfers and records the first funder and
the first activity time.

Usage: ALCHEMY_URL=... python3 scripts/trace_funders.py
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ALCHEMY_URL = os.environ["ALCHEMY_URL"]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rpc(payload, retries=8):
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
            wait = float(e.headers.get("Retry-After") or min(2**attempt, 20))
            time.sleep(wait + 1)
        except Exception:
            if attempt == retries - 1:
                raise
            time.sleep(min(2**attempt, 20))
    return None


def psql(sql, capture=True):
    cmd = ["docker", "compose", "exec", "-T", "db", "psql", "-U", "trustlist",
           "-d", "trustlist", "-v", "ON_ERROR_STOP=1", "-tAc", sql]
    return subprocess.run(cmd, capture_output=capture, text=True, check=True, cwd=ROOT).stdout


def reviewers():
    out = psql("select distinct '0x'||encode(reviewer,'hex') from feedback")
    return [line.strip() for line in out.splitlines() if line.strip()]


def first_inbound(addr):
    """Earliest transfer into this address: who paid for it, and when."""
    res = rpc({
        "jsonrpc": "2.0", "id": 1, "method": "alchemy_getAssetTransfers",
        "params": [{
            "fromBlock": "0x0", "toBlock": "latest", "toAddress": addr,
            "category": ["external", "erc20"], "maxCount": "0xa", "order": "asc",
        }],
    })
    if "error" in res:
        return None
    transfers = res["result"].get("transfers", [])
    if not transfers:
        return None
    t = transfers[0]
    return {
        "funder": t.get("from"),
        "block": int(t["blockNum"], 16),
        "hash": t.get("hash"),
        "inbound_count": len(transfers),
    }


def outbound_count(addr):
    """How much this address does besides leaving feedback."""
    res = rpc({
        "jsonrpc": "2.0", "id": 1, "method": "alchemy_getAssetTransfers",
        "params": [{
            "fromBlock": "0x0", "toBlock": "latest", "fromAddress": addr,
            "category": ["external", "erc20"], "maxCount": "0x64", "order": "asc",
        }],
    })
    if "error" in res:
        return 0
    return len(res["result"].get("transfers", []))


def main():
    addrs = reviewers()
    print(f"tracing {len(addrs)} reviewer addresses", file=sys.stderr)

    def work(a):
        try:
            fi = first_inbound(a)
            oc = outbound_count(a)
            time.sleep(0.25)
            return (a, fi, oc)
        except Exception as e:
            print(f"  {a}: {e}", file=sys.stderr)
            return (a, None, 0)

    rows = []
    with ThreadPoolExecutor(max_workers=3) as ex:
        for i, (a, fi, oc) in enumerate(ex.map(work, addrs), 1):
            rows.append((a, fi, oc))
            if i % 20 == 0:
                print(f"  {i}/{len(addrs)}", file=sys.stderr)

    tsv = os.path.join(ROOT, "scripts", "funders.tsv")
    with open(tsv, "w") as f:
        for a, fi, oc in rows:
            funder = (fi or {}).get("funder") or ""
            block = (fi or {}).get("block") or 0
            f.write(f"{a[2:]}\t{funder[2:] if funder else ''}\t{block}\t{oc}\n")

    psql("drop table if exists funder_stage; "
         "create table funder_stage (reviewer_hex text, funder_hex text, "
         "first_block bigint, outbound_count int)", capture=False)
    with open(tsv) as f:
        subprocess.run(
            ["docker", "compose", "exec", "-T", "db", "psql", "-U", "trustlist",
             "-d", "trustlist", "-v", "ON_ERROR_STOP=1", "-c",
             "\\copy funder_stage from pstdin"],
            stdin=f, check=True, cwd=ROOT)
    psql("""
      insert into reviewer_funding (reviewer, funder, first_block, outbound_count, traced_at)
      select decode(reviewer_hex,'hex'),
             case when funder_hex = '' then null else decode(funder_hex,'hex') end,
             first_block, outbound_count, now()
      from funder_stage
      on conflict (reviewer) do update set
        funder = excluded.funder,
        first_block = excluded.first_block,
        outbound_count = excluded.outbound_count,
        traced_at = now();
      drop table funder_stage;
    """, capture=False)

    traced = psql("select count(*) from reviewer_funding where funder is not null").strip()
    clusters = psql("select count(*) from (select funder from reviewer_funding "
                    "where funder is not null group by funder having count(*) >= 2) t").strip()
    print(f"traced {traced} reviewers to a funder, {clusters} funders paid for more than one",
          file=sys.stderr)


if __name__ == "__main__":
    main()

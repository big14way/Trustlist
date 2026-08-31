#!/usr/bin/env python3
"""Token Screen: what a BSC token's owner can still do to you.

Answers one question before a swap: if I buy this, what powers does someone
else keep over my position? Every finding is read from chain and every one
names the evidence, because a risk report you cannot check is just a vibe.

Read only. It holds no funds, requests no approvals, and signs nothing.

Standard library only, deliberately: an agent anyone can run without
installing anything is easier to trust and easier to keep alive.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

RPC = os.environ.get("BSC_RPC_HTTP", "https://bsc-rpc.publicnode.com")
TIMEOUT = 15
# Some public BSC endpoints answer 403 to urllib's default user agent. Saying
# who we are is polite anyway, and it is what the other two agents do.
USER_AGENT = "TrustList-TokenScreen/0.1 (+https://github.com/big14way/Trustlist)"

# EIP-1967 implementation slot. A non zero value here means the code behind
# this address can be replaced, which outranks every other finding: whatever
# the current logic does is not a promise about tomorrow.
EIP1967_IMPL = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
# EIP-1967 admin slot, the address allowed to do the replacing.
EIP1967_ADMIN = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"

# Selectors we look for in the deployed bytecode. Presence is evidence that
# the function exists, not proof it is reachable, and the report says so.
# Every selector below was checked with `cast sig` on 31 August 2026 rather
# than written from memory. One of them was wrong when it was: setFees was
# recorded as b0f5a6cf and is actually 0b78f9c0, which would have quietly
# never matched. test_screen.py pins all six so an edit cannot drift them.
SELECTORS: Dict[str, Tuple[str, str, str]] = {
    # name: (selector, severity, what it means for a holder)
    "mint(address,uint256)": ("40c10f19", "high", "supply can be increased, diluting holders"),
    "pause()": ("8456cb59", "high", "transfers can be frozen"),
    "blacklist(address)": ("f9f92be4", "high", "an address can be blocked from transferring"),
    "setFees(uint256,uint256)": ("0b78f9c0", "medium", "transfer fees can be changed"),
    "setMaxTxAmount(uint256)": ("ec28438a", "medium", "the maximum trade size can be changed"),
    "burnFrom(address,uint256)": ("79cc6790", "medium", "tokens can be destroyed from an address"),
}

OWNER_CALLS = ["owner()", "getOwner()"]
ZERO = "0x" + "0" * 40


class RpcError(RuntimeError):
    pass


def rpc(method: str, params: List[Any]) -> Any:
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(
        RPC, body, {"content-type": "application/json", "user-agent": USER_AGENT}
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            out = json.loads(r.read())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
        raise RpcError(f"{method} failed: {e}") from e
    if "error" in out:
        raise RpcError(f"{method}: {out['error'].get('message')}")
    return out.get("result")


def selector(sig: str) -> str:
    """keccak of a signature, first four bytes, via the node.

    The standard library has no keccak256 and this agent takes no
    dependencies, so the chain computes it. Cached, because the set is small
    and fixed.
    """
    if sig in _SEL_CACHE:
        return _SEL_CACHE[sig]
    out = rpc("web3_sha3", ["0x" + sig.encode().hex()])
    _SEL_CACHE[sig] = out[2:10]
    return _SEL_CACHE[sig]


_SEL_CACHE: Dict[str, str] = {}


def call(to: str, sig: str) -> Optional[str]:
    """eth_call a zero argument function. None when it reverts or is absent."""
    try:
        out = rpc("eth_call", [{"to": to, "data": "0x" + selector(sig)}, "latest"])
    except RpcError:
        return None
    if out in (None, "0x", ""):
        return None
    return out


def as_address(word: Optional[str]) -> Optional[str]:
    if not word or len(word) < 66:
        return None
    return "0x" + word[-40:]


def as_bool(word: Optional[str]) -> Optional[bool]:
    if not word:
        return None
    return int(word, 16) != 0


def code_of(address: str) -> str:
    return rpc("eth_getCode", [address, "latest"]) or "0x"


def storage_address(address: str, slot: str) -> Optional[str]:
    word = rpc("eth_getStorageAt", [address, slot, "latest"])
    addr = as_address(word)
    if addr is None or addr.lower() == ZERO:
        return None
    return addr


def screen(token: str) -> Dict[str, Any]:
    """Everything below is read from chain at the moment of the call."""
    token = token.lower()
    findings: List[Dict[str, str]] = []

    code = code_of(token)
    if code in ("0x", ""):
        return {
            "token": token,
            "verdict": "not a contract",
            "detail": "there is no code at this address on BSC, so it is not a token",
            "findings": [],
            "checked": [],
        }

    # Upgradeability first. If the logic can be swapped, everything else in
    # this report describes only today's code.
    impl = storage_address(token, EIP1967_IMPL)
    admin = storage_address(token, EIP1967_ADMIN)
    target = impl or token
    if impl:
        findings.append({
            "severity": "high",
            "finding": "upgradeable",
            "detail": (
                "an EIP-1967 proxy: the code behind this address can be replaced, "
                f"so these findings describe the current implementation {impl} only"
            ),
            "evidence": f"storage slot {EIP1967_IMPL} holds {impl}",
        })
        if admin:
            findings.append({
                "severity": "high",
                "finding": "upgrade admin",
                "detail": f"{admin} can replace the code",
                "evidence": f"storage slot {EIP1967_ADMIN} holds {admin}",
            })

    # Who, if anyone, is in charge.
    owner = None
    for sig in OWNER_CALLS:
        owner = as_address(call(token, sig))
        if owner and owner.lower() != ZERO:
            findings.append({
                "severity": "medium",
                "finding": "owned",
                "detail": f"{owner} holds owner privileges on this token",
                "evidence": f"{sig} returned {owner}",
            })
            break
        owner = None
    if owner is None:
        findings.append({
            "severity": "none",
            "finding": "no owner",
            "detail": "no owner() or getOwner() answered, which is the safer shape",
            "evidence": "both calls reverted or returned the zero address",
        })

    # Is it frozen right now?
    paused = as_bool(call(token, "paused()"))
    if paused is True:
        findings.append({
            "severity": "high",
            "finding": "paused now",
            "detail": "transfers are currently frozen, so you may not be able to sell",
            "evidence": "paused() returned true",
        })

    # Which powers exist in the code that is actually deployed.
    target_code = code_of(target) if target != token else code
    checked: List[str] = []
    for name, (sel, severity, meaning) in SELECTORS.items():
        checked.append(name)
        if sel in target_code[2:]:
            findings.append({
                "severity": severity,
                "finding": name,
                "detail": meaning,
                "evidence": f"selector 0x{sel} appears in the deployed bytecode at {target}",
            })

    order = {"high": 0, "medium": 1, "none": 2}
    findings.sort(key=lambda f: order.get(f["severity"], 3))
    highs = [f for f in findings if f["severity"] == "high"]

    if paused is True:
        verdict = "do not buy"
    elif highs:
        verdict = "risky"
    elif any(f["severity"] == "medium" for f in findings):
        verdict = "owned, read the findings"
    else:
        verdict = "no owner powers found"

    return {
        "token": token,
        "verdict": verdict,
        "implementation": impl,
        "owner": owner,
        "findings": findings,
        "checked": checked,
        "limits": (
            "Selector presence is read from deployed bytecode. It shows a function "
            "exists, not that it is reachable or that only the owner can call it. "
            "Absence of a selector is weaker evidence still, because a proxy can "
            "route calls the bytecode here does not mention. This screens for "
            "owner power, not for every way a token can lose value."
        ),
    }

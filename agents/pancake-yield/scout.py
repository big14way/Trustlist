"""Scoring for PancakeSwap V3 pools.

Kept separate from the HTTP layer so the ranking can be tested without a
network, and so the reasoning that reaches a user is generated from the same
numbers the score is computed from.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional


@dataclass(frozen=True)
class Pool:
    pool_id: str
    token0: str
    token1: str
    fee_tier: int
    tvl_usd: float
    volume_24h: float
    volume_7d: float
    fees_24h: float
    fees_7d: float

    @property
    def pair(self) -> str:
        return f"{self.token0}/{self.token1}"


def parse_pool(raw: Dict[str, Any]) -> Optional[Pool]:
    """Turn one explorer row into a Pool, or None if it is unusable."""
    try:
        return Pool(
            pool_id=str(raw["id"]),
            token0=(raw.get("token0") or {}).get("symbol") or "?",
            token1=(raw.get("token1") or {}).get("symbol") or "?",
            fee_tier=int(raw.get("feeTier") or 0),
            tvl_usd=float(raw.get("tvlUSD") or 0.0),
            volume_24h=float(raw.get("volumeUSD24h") or 0.0),
            volume_7d=float(raw.get("volumeUSD7d") or 0.0),
            fees_24h=float(raw.get("feeUSD24h") or 0.0),
            fees_7d=float(raw.get("feeUSD7d") or 0.0),
        )
    except (KeyError, TypeError, ValueError):
        return None


def fee_apr(fees: float, tvl: float, days: float) -> float:
    """Annualised fee return. Zero when there is nothing to divide by, which
    is honest: an empty pool has no rate, it does not have an infinite one."""
    if tvl <= 0 or days <= 0:
        return 0.0
    return (fees / tvl) * (365.0 / days) * 100.0


# The size of position the ranking answers for. A rate you cannot actually
# deploy into is not a rate, so every pool is scored on what this much money
# would have earned rather than on the pool's headline number.
DEFAULT_POSITION_USD = 10_000.0


def diluted_apr(fees_7d: float, tvl: float, position: float) -> float:
    """What a position of this size would have earned, annualised.

    The fees a pool pays do not grow because you joined it: they are split
    across more liquidity. So a small pool advertising a huge rate pays that
    rate to the people already in it, and pays you a fraction of it. This is
    the single most misleading number in liquidity provision and it is the
    one this agent exists to correct.
    """
    if tvl < 0 or position <= 0 or fees_7d <= 0:
        return 0.0
    weekly_rate = fees_7d / (tvl + position)
    return weekly_rate * (365.0 / 7.0) * 100.0


def score(p: Pool, position_usd: float = DEFAULT_POSITION_USD) -> Dict[str, Any]:
    """Rank a pool on what it would actually have paid this position."""
    apr_24h = fee_apr(p.fees_24h, p.tvl_usd, 1.0)
    apr_7d = fee_apr(p.fees_7d, p.tvl_usd, 7.0)
    expected = diluted_apr(p.fees_7d, p.tvl_usd, position_usd)

    # How much of the pool this position would become. Above a few percent,
    # the entrant is the pool and the historical rate stops describing it.
    share = position_usd / (p.tvl_usd + position_usd) if p.tvl_usd >= 0 else 1.0

    # Consistency is reported as a warning rather than folded into the score,
    # because it says whether the rate is likely to repeat, not what it is.
    consistency = min(1.0, apr_7d / apr_24h) if apr_24h > 0 else 0.0
    turnover = min(1.0, p.volume_24h / p.tvl_usd) if p.tvl_usd > 0 else 0.0

    return {
        "pool": p.pool_id,
        "pair": p.pair,
        "fee_tier_bps": p.fee_tier / 100.0,
        "tvl_usd": round(p.tvl_usd, 2),
        "volume_24h_usd": round(p.volume_24h, 2),
        "fees_24h_usd": round(p.fees_24h, 2),
        "fees_7d_usd": round(p.fees_7d, 2),
        "pool_fee_apr_24h_pct": round(apr_24h, 2),
        "pool_fee_apr_7d_pct": round(apr_7d, 2),
        "position_usd": position_usd,
        "your_share_pct": round(share * 100.0, 2),
        "expected_apr_pct": round(expected, 2),
        "consistency": round(consistency, 3),
        "turnover": round(turnover, 3),
    }


def explain(s: Dict[str, Any]) -> str:
    """Say why, in the words a person would use."""
    if s["pool_fee_apr_7d_pct"] <= 0:
        return (
            f"{s['pair']} paid its liquidity providers nothing measurable over the "
            "last week, so there is no rate to report."
        )
    bits = [
        f"{s['pair']} at {s['fee_tier_bps']:g} bps would have paid about "
        f"{s['expected_apr_pct']:.1f} percent annualised on "
        f"{s['position_usd']:,.0f} dollars over the last week"
    ]
    gap = s["pool_fee_apr_7d_pct"] - s["expected_apr_pct"]
    if gap > 1.0 and s["your_share_pct"] >= 1.0:
        bits.append(
            f"the pool itself paid {s['pool_fee_apr_7d_pct']:.1f} percent, but a "
            f"position this size would be {s['your_share_pct']:.1f} percent of the "
            "pool and the fees do not grow because you joined"
        )
    if s["consistency"] < 0.5 and s["pool_fee_apr_24h_pct"] > s["pool_fee_apr_7d_pct"]:
        bits.append(
            f"yesterday was unusually busy at {s['pool_fee_apr_24h_pct']:.1f} percent "
            "for the pool, so treat the higher number as a spike rather than the rate"
        )
    if s["turnover"] < 0.05:
        bits.append(
            "very little of this liquidity is being traded against, which is why "
            "the fee return is low despite the size"
        )
    return ". ".join(bits) + "."


def rank(
    raw_pools: List[Dict[str, Any]],
    asset: Optional[str] = None,
    position_usd: float = DEFAULT_POSITION_USD,
) -> List[Dict[str, Any]]:
    """Score every usable pool, optionally filtered to one asset."""
    out = []
    for raw in raw_pools:
        p = parse_pool(raw)
        if p is None:
            continue
        if asset:
            want = asset.strip().upper()
            if want not in (p.token0.upper(), p.token1.upper()):
                continue
        s = score(p, position_usd)
        s["why"] = explain(s)
        out.append(s)
    out.sort(key=lambda s: s["expected_apr_pct"], reverse=True)
    return out

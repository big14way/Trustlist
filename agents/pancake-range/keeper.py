"""Range analysis for a PancakeSwap V3 concentrated liquidity position.

Kept free of network calls so the arithmetic can be tested exactly. The
server hands it what it read from chain and it says whether the position is
still earning, how far out of range it has drifted, and what range would put
it back to work.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional

# Uniswap style tick spacing: each tick is a 0.01 percent price step.
TICK_BASE = 1.0001


@dataclass(frozen=True)
class Position:
    token_id: int
    token0: str
    token1: str
    fee: int
    tick_lower: int
    tick_upper: int
    liquidity: int
    decimals0: int = 18
    decimals1: int = 18


def tick_to_price(tick: int, decimals0: int = 18, decimals1: int = 18) -> float:
    """Price of token0 denominated in token1, adjusted for decimals."""
    return (TICK_BASE**tick) * (10 ** (decimals0 - decimals1))


def price_gap_pct(from_tick: int, to_tick: int) -> float:
    """How far apart two ticks are as a percentage price move."""
    return (TICK_BASE ** (to_tick - from_tick) - 1.0) * 100.0


def analyse(p: Position, current_tick: int) -> Dict[str, Any]:
    """Report whether the position is earning, and by how much it has drifted."""
    width = p.tick_upper - p.tick_lower
    in_range = p.tick_lower <= current_tick < p.tick_upper
    closed = p.liquidity == 0

    if current_tick < p.tick_lower:
        # Price fell through the bottom: the position is entirely token0.
        drift_ticks = p.tick_lower - current_tick
        side = "below"
    elif current_tick >= p.tick_upper:
        # Price rose through the top: the position is entirely token1.
        drift_ticks = current_tick - p.tick_upper + 1
        side = "above"
    else:
        drift_ticks = 0
        side = "inside"

    # Where in the range the price is sitting, 0 at the lower edge and 1 at
    # the upper. Useful even while in range: 0.95 means it is about to leave.
    position_in_range = (current_tick - p.tick_lower) / width if width > 0 else 0.0

    return {
        "token_id": p.token_id,
        "pair": f"{p.token0}/{p.token1}",
        "fee_bps": p.fee / 100.0,
        "liquidity": str(p.liquidity),
        "closed": closed,
        "tick_lower": p.tick_lower,
        "tick_upper": p.tick_upper,
        "tick_current": current_tick,
        "range_width_ticks": width,
        "in_range": in_range and not closed,
        "drift_side": side,
        "drift_ticks": drift_ticks,
        "drift_pct": round(abs(price_gap_pct(current_tick, p.tick_lower if side == "below" else p.tick_upper)), 4)
        if side != "inside"
        else 0.0,
        "position_in_range": round(position_in_range, 4),
        "price_lower": tick_to_price(p.tick_lower, p.decimals0, p.decimals1),
        "price_upper": tick_to_price(p.tick_upper, p.decimals0, p.decimals1),
        "price_current": tick_to_price(current_tick, p.decimals0, p.decimals1),
    }


def propose_range(p: Position, current_tick: int, tick_spacing: int) -> Dict[str, Any]:
    """A replacement range of the same width, centred on the current price.

    Keeping the width is deliberate: the owner chose how concentrated they
    wanted to be, and a keeper that quietly widens or narrows that is making
    a decision it was not asked to make.
    """
    width = p.tick_upper - p.tick_lower
    half = width // 2
    raw_lower = current_tick - half
    # Ranges must sit on the pool's tick spacing.
    lower = (raw_lower // tick_spacing) * tick_spacing
    upper = lower + width
    return {
        "new_tick_lower": lower,
        "new_tick_upper": upper,
        "width_preserved": upper - lower == width,
        "tick_spacing": tick_spacing,
        "new_price_lower": tick_to_price(lower, p.decimals0, p.decimals1),
        "new_price_upper": tick_to_price(upper, p.decimals0, p.decimals1),
    }


# Leaving and re-entering a range costs gas and realises impermanent loss, so
# a keeper that rebalances on every wobble loses money for its owner. These
# thresholds are the point at which acting is worth more than waiting.
DRIFT_TO_ACT_PCT = 1.0
EDGE_WARNING = 0.9


def recommend(
    p: Position,
    current_tick: int,
    tick_spacing: int,
    drift_to_act_pct: float = DRIFT_TO_ACT_PCT,
) -> Dict[str, Any]:
    """What the owner should do, and plainly why."""
    a = analyse(p, current_tick)

    if a["closed"]:
        return {
            **a,
            "action": "none",
            "reason": "This position has no liquidity left, so there is nothing to keep in range.",
            "proposed": None,
        }

    if a["in_range"]:
        edge = a["position_in_range"]
        if edge >= EDGE_WARNING or edge <= (1.0 - EDGE_WARNING):
            near = "upper" if edge >= EDGE_WARNING else "lower"
            return {
                **a,
                "action": "watch",
                "reason": (
                    f"Still earning, but the price is sitting near the {near} edge of "
                    f"the range. If it keeps moving this way the position stops "
                    f"earning and will need a new range."
                ),
                "proposed": None,
            }
        return {
            **a,
            "action": "none",
            "reason": (
                "The price is inside the range, so this position is earning fees. "
                "Nothing to do."
            ),
            "proposed": None,
        }

    if a["drift_pct"] < drift_to_act_pct:
        return {
            **a,
            "action": "watch",
            "reason": (
                f"The price has just left the range, by {a['drift_pct']:.2f} percent. "
                f"Rebalancing costs gas and locks in the loss from the move, so it is "
                f"worth waiting until the drift is at least {drift_to_act_pct:.2f} "
                f"percent in case the price comes back."
            ),
            "proposed": None,
        }

    side = a["drift_side"]
    holding = p.token0 if side == "below" else p.token1
    return {
        **a,
        "action": "rebalance",
        "reason": (
            f"The price has moved {a['drift_pct']:.2f} percent {side} the range, so "
            f"this position has stopped earning fees and is now entirely {holding}. "
            f"Moving the range back around the current price puts it to work again."
        ),
        "proposed": propose_range(p, current_tick, tick_spacing),
    }

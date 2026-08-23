"""Tests for the range keeper.

The failure modes that cost an owner real money are: telling them to
rebalance on a wobble that reverses, missing that they have stopped earning
entirely, and quietly changing how concentrated their position is. Those are
what these cover.
"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from keeper import (  # noqa: E402
    Position,
    analyse,
    price_gap_pct,
    propose_range,
    recommend,
    tick_to_price,
)


def pos(lower=4850, upper=5450, liquidity=8_066_996_433_266_099_902_058):
    # Shaped after a real CAKE/USDT position on BSC, token 7238953.
    return Position(7238953, "CAKE", "USDT", 2500, lower, upper, liquidity)


class TickMath(unittest.TestCase):
    def test_tick_zero_is_parity(self):
        self.assertAlmostEqual(tick_to_price(0), 1.0, places=9)

    def test_each_tick_is_one_basis_point(self):
        self.assertAlmostEqual(price_gap_pct(0, 1), 0.01, places=6)
        self.assertAlmostEqual(price_gap_pct(0, 100), 1.005, places=2)

    def test_decimals_are_applied(self):
        # A token0 with fewer decimals than token1 shifts the quoted price.
        self.assertAlmostEqual(tick_to_price(0, 6, 18), 1e-12, places=18)


class InRange(unittest.TestCase):
    def test_price_inside_the_range_is_earning(self):
        a = analyse(pos(), 5100)
        self.assertTrue(a["in_range"])
        self.assertEqual(a["drift_side"], "inside")
        self.assertEqual(a["drift_pct"], 0.0)

    def test_the_lower_bound_is_inclusive_and_the_upper_is_not(self):
        # Matches the pool's own convention, so we never claim a position is
        # earning when the pool has already stopped paying it.
        self.assertTrue(analyse(pos(), 4850)["in_range"])
        self.assertFalse(analyse(pos(), 5450)["in_range"])

    def test_position_in_range_locates_the_price(self):
        self.assertAlmostEqual(analyse(pos(), 4850)["position_in_range"], 0.0, places=4)
        self.assertAlmostEqual(analyse(pos(), 5150)["position_in_range"], 0.5, places=4)


class Recommendations(unittest.TestCase):
    def test_a_healthy_position_is_left_alone(self):
        r = recommend(pos(), 5150, 50)
        self.assertEqual(r["action"], "none")

    def test_sitting_near_the_edge_is_a_warning_not_an_order(self):
        r = recommend(pos(), 5430, 50)
        self.assertEqual(r["action"], "watch")
        self.assertIn("upper edge", r["reason"])
        self.assertIsNone(r["proposed"])

    def test_a_small_drift_does_not_trigger_churn(self):
        # Just outside the range: acting here costs gas and locks in the loss
        # for a move that may reverse within the hour.
        r = recommend(pos(), 5460, 50)
        self.assertEqual(r["action"], "watch")
        self.assertIn("worth waiting", r["reason"])
        self.assertIsNone(r["proposed"])

    def test_a_real_drift_triggers_a_rebalance_with_a_reason(self):
        r = recommend(pos(), 5600, 50)
        self.assertEqual(r["action"], "rebalance")
        self.assertIn("stopped earning", r["reason"])
        self.assertIsNotNone(r["proposed"])

    def test_it_says_which_token_the_owner_is_now_holding(self):
        # Above the range the position is entirely token1, below it token0.
        self.assertIn("USDT", recommend(pos(), 5600, 50)["reason"])
        self.assertIn("CAKE", recommend(pos(), 4600, 50)["reason"])

    def test_a_closed_position_is_never_rebalanced(self):
        r = recommend(pos(liquidity=0), 9999, 50)
        self.assertEqual(r["action"], "none")
        self.assertTrue(r["closed"])
        self.assertIsNone(r["proposed"])


class ProposedRange(unittest.TestCase):
    def test_the_owners_chosen_width_is_preserved(self):
        p = pos()
        prop = propose_range(p, 6000, 50)
        self.assertTrue(prop["width_preserved"])
        self.assertEqual(
            prop["new_tick_upper"] - prop["new_tick_lower"],
            p.tick_upper - p.tick_lower,
            "a keeper must not quietly change how concentrated a position is",
        )

    def test_the_new_range_sits_on_the_pools_tick_spacing(self):
        prop = propose_range(pos(), 6013, 50)
        self.assertEqual(prop["new_tick_lower"] % 50, 0)

    def test_the_new_range_contains_the_current_price(self):
        for tick in (6000, 6013, -1200, 0):
            prop = propose_range(pos(), tick, 50)
            self.assertLessEqual(prop["new_tick_lower"], tick)
            self.assertGreater(prop["new_tick_upper"], tick)


if __name__ == "__main__":
    unittest.main(verbosity=2)

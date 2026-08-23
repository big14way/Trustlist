"""Tests for the yield scout's ranking.

The ranking is the whole product of this agent, so the cases below are the
ones a user would be hurt by getting wrong: a pool that spiked yesterday
being sold as a steady rate, a pool too thin to enter being ranked top, and
an empty pool showing an infinite return.
"""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scout import diluted_apr, fee_apr, parse_pool, rank, score  # noqa: E402


def raw(**kw):
    base = {
        "id": "0xpool",
        "token0": {"symbol": "AAA"},
        "token1": {"symbol": "BBB"},
        "feeTier": 500,
        "tvlUSD": 1_000_000.0,
        "volumeUSD24h": 200_000.0,
        "volumeUSD7d": 1_400_000.0,
        "feeUSD24h": 100.0,
        "feeUSD7d": 700.0,
    }
    base.update(kw)
    return base


class FeeApr(unittest.TestCase):
    def test_annualises_from_real_fees_and_tvl(self):
        # 100 dollars a day on 1,000,000 is 3.65 percent a year.
        self.assertAlmostEqual(fee_apr(100.0, 1_000_000.0, 1.0), 3.65, places=2)
        self.assertAlmostEqual(fee_apr(700.0, 1_000_000.0, 7.0), 3.65, places=2)

    def test_an_empty_pool_has_no_rate_rather_than_an_infinite_one(self):
        self.assertEqual(fee_apr(50.0, 0.0, 1.0), 0.0)
        self.assertEqual(fee_apr(50.0, -1.0, 1.0), 0.0)


class Dilution(unittest.TestCase):
    """The single most misleading number in liquidity provision is a headline
    rate you cannot actually deploy into. These are the cases that matter."""

    def test_your_deposit_does_not_create_new_fees(self):
        # A pool with 5,000 dollars paying 350 a week looks spectacular, but
        # a 10,000 dollar position becomes two thirds of it.
        pool_rate = fee_apr(350.0, 5_000.0, 7.0)
        yours = diluted_apr(350.0, 5_000.0, 10_000.0)
        self.assertGreater(pool_rate, 300.0, "the headline rate really is huge")
        self.assertLess(yours, pool_rate / 2, "and you would get a fraction of it")

    def test_a_deep_pool_barely_dilutes(self):
        pool_rate = fee_apr(7_000.0, 1_000_000.0, 7.0)
        yours = diluted_apr(7_000.0, 1_000_000.0, 10_000.0)
        self.assertAlmostEqual(pool_rate, yours, delta=0.5)

    def test_a_pool_paying_nothing_yields_nothing(self):
        self.assertEqual(diluted_apr(0.0, 1_000.0, 10_000.0), 0.0)


class Scoring(unittest.TestCase):
    def test_the_thin_pool_loses_to_the_deep_one_at_a_real_position_size(self):
        # Identical headline rates, wildly different achievable rates.
        thin = score(parse_pool(raw(id="0xthin", tvlUSD=5_000.0, feeUSD7d=350.0,
                                    volumeUSD24h=1_000.0)), 10_000.0)
        deep = score(parse_pool(raw(id="0xdeep", tvlUSD=1_000_000.0, feeUSD7d=70_000.0,
                                    volumeUSD24h=300_000.0)), 10_000.0)
        self.assertAlmostEqual(thin["pool_fee_apr_7d_pct"], deep["pool_fee_apr_7d_pct"], places=2)
        self.assertGreater(
            deep["expected_apr_pct"],
            thin["expected_apr_pct"],
            "the pool you can actually enter should win",
        )

    def test_a_spike_yesterday_is_called_out_in_the_reasoning(self):
        spike = rank([raw(feeUSD24h=1000.0, feeUSD7d=700.0)])[0]
        self.assertIn("spike", spike["why"])

    def test_dilution_is_explained_when_it_matters(self):
        thin = rank([raw(tvlUSD=20_000.0, feeUSD7d=700.0)], position_usd=10_000.0)[0]
        self.assertGreater(thin["your_share_pct"], 1.0)
        self.assertIn("do not grow because you joined", thin["why"])

    def test_every_input_behind_the_answer_is_reported(self):
        s = score(parse_pool(raw()))
        for k in (
            "tvl_usd", "volume_24h_usd", "fees_7d_usd",
            "pool_fee_apr_24h_pct", "pool_fee_apr_7d_pct",
            "position_usd", "your_share_pct", "expected_apr_pct",
            "consistency", "turnover",
        ):
            self.assertIn(k, s, f"{k} must be visible so a user can disagree with us")


class Parsing(unittest.TestCase):
    def test_unusable_rows_are_skipped_not_guessed(self):
        self.assertIsNone(parse_pool({"id": "x", "tvlUSD": "not a number"}))
        self.assertIsNone(parse_pool({}))

    def test_missing_symbols_do_not_crash_the_scan(self):
        p = parse_pool({"id": "0x1", "feeTier": 100, "tvlUSD": 1.0,
                        "volumeUSD24h": 0, "volumeUSD7d": 0,
                        "feeUSD24h": 0, "feeUSD7d": 0})
        self.assertIsNotNone(p)
        self.assertEqual(p.pair, "?/?")


class Ranking(unittest.TestCase):
    def test_filters_to_the_asset_asked_about(self):
        pools = [
            raw(id="0xa", token0={"symbol": "CAKE"}, token1={"symbol": "USDT"}),
            raw(id="0xb", token0={"symbol": "WBNB"}, token1={"symbol": "USDT"}),
        ]
        out = rank(pools, "cake")
        self.assertEqual(len(out), 1)
        self.assertEqual(out[0]["pair"], "CAKE/USDT")

    def test_orders_by_what_a_real_position_would_earn(self):
        pools = [
            raw(id="0xthin", tvlUSD=5_000.0, feeUSD7d=350.0, volumeUSD24h=100.0),
            raw(id="0xdeep", tvlUSD=1_000_000.0, feeUSD7d=70_000.0, volumeUSD24h=300_000.0),
        ]
        out = rank(pools, position_usd=10_000.0)
        self.assertEqual(out[0]["pool"], "0xdeep", "the pool you can enter comes first")

    def test_a_pool_paying_nothing_says_so_plainly(self):
        out = rank([raw(feeUSD24h=0.0, feeUSD7d=0.0)])
        self.assertIn("nothing measurable", out[0]["why"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

#!/usr/bin/env python3
"""Offline tests for the token screener.

The selector table is the part that can be wrong without anything failing,
so it is pinned here. keccak256 is not in the standard library and this agent
takes no dependencies, so these are the values from `cast sig`, recorded on
31 August 2026. One of them was wrong when it was written from memory, which
is the whole reason this file exists.
"""

import unittest

import screen


class Selectors(unittest.TestCase):
    KNOWN = {
        "mint(address,uint256)": "40c10f19",
        "pause()": "8456cb59",
        "blacklist(address)": "f9f92be4",
        "setFees(uint256,uint256)": "0b78f9c0",
        "setMaxTxAmount(uint256)": "ec28438a",
        "burnFrom(address,uint256)": "79cc6790",
    }

    def test_every_selector_matches_the_verified_value(self):
        for sig, (sel, _sev, _why) in screen.SELECTORS.items():
            self.assertIn(sig, self.KNOWN, f"{sig} has no verified selector on record")
            self.assertEqual(sel, self.KNOWN[sig], f"{sig} selector drifted")

    def test_no_verified_selector_was_dropped(self):
        for sig in self.KNOWN:
            self.assertIn(sig, screen.SELECTORS)

    def test_selectors_are_four_bytes_of_lowercase_hex(self):
        for sig, (sel, _s, _w) in screen.SELECTORS.items():
            self.assertEqual(len(sel), 8, sig)
            self.assertEqual(sel, sel.lower(), sig)
            int(sel, 16)

    def test_every_finding_has_a_severity_we_rank(self):
        for sig, (_sel, sev, _w) in screen.SELECTORS.items():
            self.assertIn(sev, ("high", "medium"), sig)


class Decoding(unittest.TestCase):
    def test_an_address_is_the_last_twenty_bytes_of_the_word(self):
        word = "0x" + "00" * 12 + "f68a4b64162906eff0ff6ae34e2bb1cd42fef62d"
        self.assertEqual(screen.as_address(word), "0xf68a4b64162906eff0ff6ae34e2bb1cd42fef62d")

    def test_a_short_word_is_not_an_address(self):
        self.assertIsNone(screen.as_address("0x00"))
        self.assertIsNone(screen.as_address(None))

    def test_bools(self):
        self.assertTrue(screen.as_bool("0x" + "0" * 63 + "1"))
        self.assertFalse(screen.as_bool("0x" + "0" * 64))
        self.assertIsNone(screen.as_bool(None))

    def test_the_eip1967_slots_are_the_standard_ones(self):
        # Defined by the EIP as keccak256("eip1967.proxy.implementation") - 1.
        # Getting these wrong would silently report every proxy as immutable.
        self.assertEqual(
            screen.EIP1967_IMPL,
            "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc",
        )
        self.assertEqual(
            screen.EIP1967_ADMIN,
            "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103",
        )


if __name__ == "__main__":
    unittest.main()

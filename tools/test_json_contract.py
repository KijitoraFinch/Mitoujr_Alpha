#!/usr/bin/env python3
"""Regression tests for strict specification JSON handling."""

from __future__ import annotations

import unittest

from json_contract import ContractJsonError, equal_exact, loads


class JsonContractTest(unittest.TestCase):
    def test_duplicate_keys_are_rejected(self) -> None:
        with self.assertRaises(ContractJsonError):
            loads('{"key": 1, "key": 2}', source="duplicate-test")

    def test_non_finite_numbers_are_rejected(self) -> None:
        with self.assertRaises(ContractJsonError):
            loads('{"value": NaN}', source="non-finite-test")
        with self.assertRaises(ContractJsonError):
            loads('{"value": 1e400}', source="overflow-test")

    def test_lone_surrogates_are_rejected(self) -> None:
        with self.assertRaisesRegex(ContractJsonError, "non-scalar Unicode"):
            loads('{"value": "\\ud800"}', source="surrogate-test")

    def test_exact_comparison_distinguishes_json_types(self) -> None:
        self.assertFalse(equal_exact({"value": 1}, {"value": True}))
        self.assertFalse(equal_exact({"value": 1}, {"value": 1.0}))

    def test_exact_comparison_includes_object_order(self) -> None:
        self.assertFalse(
            equal_exact({"left": 1, "right": 2}, {"right": 2, "left": 1})
        )


if __name__ == "__main__":
    unittest.main()

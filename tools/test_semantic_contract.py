#!/usr/bin/env python3

from __future__ import annotations

import unittest

from semantic_contract import semantic_errors


class SemanticContractTest(unittest.TestCase):
    def test_rejects_inverted_range_and_float(self) -> None:
        result = {
            "patches": [
                {"edits": [{"range": {"start": 3, "end": 2}, "replacement": ""}]}
            ],
            "summary": {"count": 1.0},
        }
        self.assertEqual(len(semantic_errors(result)), 2)

    def test_rejects_false_conflict_claims(self) -> None:
        identity = {"hash": "sha256:" + ("0" * 64), "size": 0}
        result = {
            "conflicts": [
                {
                    "kind": "identity-mismatch",
                    "expected": identity,
                    "actual": dict(identity),
                },
                {
                    "kind": "range-out-of-bounds",
                    "range": {"start": 0, "end": 3},
                    "contentLength": 3,
                },
                {
                    "kind": "overlapping-edits",
                    "left": {"start": 0, "end": 1},
                    "right": {"start": 1, "end": 2},
                },
            ]
        }
        self.assertEqual(len(semantic_errors(result)), 3)

    def test_accepts_true_conflict_claims(self) -> None:
        result = {
            "conflicts": [
                {
                    "kind": "range-out-of-bounds",
                    "range": {"start": 2, "end": 4},
                    "contentLength": 3,
                },
                {
                    "kind": "overlapping-edits",
                    "left": {"start": 0, "end": 2},
                    "right": {"start": 1, "end": 3},
                },
            ]
        }
        self.assertEqual(semantic_errors(result), [])

    def test_apply_internal_failure_contract(self) -> None:
        valid = {
            "command": "apply",
            "status": "internal-error",
            "summary": {
                "errorCode": "filesystem-io",
                "operation": "flush-parent",
                "location": "docs/note.md",
                "commitState": "committed-or-unknown",
            },
        }
        self.assertEqual(semantic_errors(valid), [])
        invalid = {
            "command": "apply",
            "status": "internal-error",
            "summary": {
                "message": "/native/path: Permission denied",
            },
        }
        self.assertGreaterEqual(len(semantic_errors(invalid)), 3)

    def test_observation_scope_contract(self) -> None:
        scoped = {"artifact": "artifact:one", "local": "same"}
        invalid = {
            "artifacts": [{"id": "artifact:one"}],
            "regions": [{"id": scoped}, {"id": dict(scoped)}],
            "references": [],
            "annotations": [
                {
                    "id": {"artifact": "artifact:missing", "local": "annotation"},
                    "subject": {"kind": "resolved", "id": {"artifact": "artifact:one", "local": "absent"}},
                    "object": {"kind": "literal", "value": "value"},
                }
            ],
        }
        self.assertEqual(len(semantic_errors(invalid)), 3)

    def test_rejects_duplicate_capability_identity(self) -> None:
        capability = {
            "type": "interpreter",
            "name": "markdown",
            "version": "1",
        }
        result = {"capabilities": [capability, dict(capability)]}
        self.assertEqual(
            semantic_errors(result),
            ["$.capabilities: capability identities must be unique"],
        )


if __name__ == "__main__":
    unittest.main()

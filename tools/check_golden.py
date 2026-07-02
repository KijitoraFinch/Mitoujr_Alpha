#!/usr/bin/env python3
"""Validate retained Phase 0 and Phase 1 golden outputs."""

from __future__ import annotations

import json
import hashlib
import subprocess
import sys
from copy import deepcopy
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]

GOLDEN_FILES = {
    "golden/scan/basic.expected.json": "scan",
    "golden/inspect/linking.expected.json": "inspect",
    "golden/resolve/latency-run-a.expected.json": "resolve",
    "golden/check/basic.expected.json": "check",
    "golden/derive/linking-to-sidecar.expected.json": "derive",
}

NORMAL_FORM_FIXTURE = "golden/normal-form/representative.command-result.json"
TRANSITION_FIXTURES = {
    "golden/workspace-transitions/apply-title-replacement.json": "apply-title-replacement",
    "golden/workspace-transitions/apply-identity-mismatch.json": "apply-identity-mismatch",
    "golden/workspace-transitions/apply-range-out-of-bounds.json": "apply-range-out-of-bounds",
    "golden/workspace-transitions/apply-overlap.json": "apply-overlap",
    "golden/workspace-transitions/apply-result-identity-mismatch.json": "apply-result-identity-mismatch",
    "golden/workspace-transitions/apply-repeated-no-op.json": "apply-repeated-no-op",
}
COMMAND_RESULT_SCHEMA = "schemas/command-result.schema.json"


def fail(message: str) -> None:
    print(f"golden check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    for path, command in GOLDEN_FILES.items():
        full_path = ROOT / path
        if not full_path.is_file():
            fail(f"missing golden file: {path}")

        with full_path.open(encoding="utf-8") as file:
            data = json.load(file)

        if data.get("schemaVersion") != "0.0.0-phase0":
            fail(f"{path} has unexpected schemaVersion")
        if data.get("command") != command:
            fail(f"{path} has command {data.get('command')!r}, expected {command!r}")
        if data.get("status") != "scaffold-only":
            fail(f"{path} must remain explicitly marked scaffold-only in Phase 0")

    schema_data = json.loads((ROOT / COMMAND_RESULT_SCHEMA).read_text())
    Draft202012Validator.check_schema(schema_data)
    validator = Draft202012Validator(schema_data)
    fixture = json.loads((ROOT / NORMAL_FORM_FIXTURE).read_text())
    errors = sorted(validator.iter_errors(fixture), key=lambda error: list(error.path))
    if errors:
        fail(f"{NORMAL_FORM_FIXTURE} does not match schema: {errors[0].message}")

    generated = subprocess.run(
        [
            "dune",
            "exec",
            "--root",
            "sugar",
            "test/normal_fixture.exe",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    if json.loads(generated.stdout) != fixture:
        fail(f"{NORMAL_FORM_FIXTURE} differs from the OCaml encoder output")

    for required_collection in [
        "diagnostics",
        "patches",
        "changedArtifacts",
        "conflicts",
        "snapshots",
    ]:
        invalid = deepcopy(fixture)
        del invalid[required_collection]
        if validator.is_valid(invalid):
            fail(f"schema accepts missing collection: {required_collection}")

    invalid = deepcopy(fixture)
    invalid["summary"] = None
    if validator.is_valid(invalid):
        fail("schema accepts null summary")

    invalid = deepcopy(fixture)
    invalid["diagnostics"][0]["location"] = None
    if validator.is_valid(invalid):
        fail("schema accepts null location")

    invalid = deepcopy(fixture)
    invalid["diagnostics"][0]["suggestedFixes"][0]["edits"] = []
    if validator.is_valid(invalid):
        fail("schema accepts a patch with no edits")

    invalid = deepcopy(fixture)
    invalid["status"] = "ok"
    invalid["diagnostics"] = []
    if validator.is_valid(invalid):
        fail("schema accepts ok status with conflicts")

    invalid = deepcopy(fixture)
    invalid["conflicts"] = []
    if validator.is_valid(invalid):
        fail("schema accepts conflict status with no conflicts")

    invalid = deepcopy(fixture)
    invalid["status"] = "applied"
    invalid["changedArtifacts"] = [
        {
            "path": "docs/README%20%FF.md",
            "before": {
                "hash": "sha256:2050a5c6f02df17a2a0c31d68580e91c8eff3c63b1de2e005749dfa7710c6210",
                "size": 6,
            },
            "after": {
                "hash": "sha256:b5e07ae6610ae6dd33f1903bea1a87e0e874347512063488bd428b4259c0e3f1",
                "size": 8,
            },
        }
    ]
    if validator.is_valid(invalid):
        fail("schema accepts applied status with conflicts")

    invalid = deepcopy(fixture)
    invalid["conflicts"][0].pop("expected")
    if validator.is_valid(invalid):
        fail("schema accepts identity-mismatch without expected identity")

    invalid = deepcopy(fixture)
    invalid["conflicts"][0] = {
        "kind": "missing-artifact",
        "patchId": "patch:readme-title",
        "target": "docs/README%20%FF.md",
        "range": {"start": 0, "end": 1},
    }
    if validator.is_valid(invalid):
        fail("schema accepts missing-artifact with range detail")

    valid = deepcopy(fixture)
    valid["conflicts"][0] = {
        "kind": "filesystem-safety",
        "patchId": "patch:readme-title",
        "target": "docs/README%20%FF.md",
        "reason": "target-is-symlink",
    }
    if not validator.is_valid(valid):
        fail("schema rejects filesystem-safety conflict")

    invalid = deepcopy(valid)
    invalid["conflicts"][0].pop("reason")
    if validator.is_valid(invalid):
        fail("schema accepts filesystem-safety conflict without reason")

    invalid = deepcopy(fixture)
    invalid["snapshots"][0]["target"]["selector"]["where"] = {}
    if validator.is_valid(invalid):
        fail("schema accepts a row filter with no conditions")

    invalid = deepcopy(fixture)
    invalid["snapshots"][0]["target"]["selector"]["where"]["metric"] = None
    if validator.is_valid(invalid):
        fail("schema accepts a null row-filter literal")

    invalid = deepcopy(fixture)
    invalid["snapshots"][0]["target"]["selector"]["where"]["metric"] = 1.5
    if validator.is_valid(invalid):
        fail("schema accepts an inexact row-filter number")

    for literal in ["latency", 42, True]:
        valid = deepcopy(fixture)
        valid["snapshots"][0]["target"]["selector"]["where"]["metric"] = literal
        if not validator.is_valid(valid):
            fail(f"schema rejects row-filter literal: {literal!r}")

    for path in [
        "docs/README%20%FF.md",
        "percent/%25.txt",
        "reserved/%5Bbracket%5D.txt",
    ]:
        valid = deepcopy(fixture)
        valid["conflicts"][0]["target"] = path
        if not validator.is_valid(valid):
            fail(f"schema rejects canonical workspace path: {path!r}")

    for path in [
        ".",
        "..",
        "docs/.",
        "docs/..",
        "docs/%2E",
        "docs/%2E%2E",
        "docs/%41.txt",
        "docs/%2Fslash",
        "docs/%00nul",
        "docs/lower%ff",
        "docs//name",
        "/docs/name",
    ]:
        invalid = deepcopy(fixture)
        invalid["conflicts"][0]["target"] = path
        if validator.is_valid(invalid):
            fail(f"schema accepts non-canonical workspace path: {path!r}")

    required_transition_fields = {
        "schemaVersion",
        "caseId",
        "initialSnapshot",
        "command",
        "result",
        "finalSnapshot",
        "exitClass",
    }
    for transition_path, case_id in TRANSITION_FIXTURES.items():
        transition = json.loads((ROOT / transition_path).read_text())
        generated_transition = subprocess.run(
            [
                "dune",
                "exec",
                "--root",
                "sugar",
                "test/transition_fixture.exe",
                case_id,
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        if json.loads(generated_transition.stdout) != transition:
            fail(f"{transition_path} differs from the OCaml transition output")

        if set(transition) != required_transition_fields:
            fail(f"{transition_path} has an invalid top-level structure")
        if transition["schemaVersion"] != "1":
            fail(f"{transition_path} has an unexpected schemaVersion")
        if transition["caseId"] != case_id:
            fail(f"{transition_path} has unexpected caseId")
        if transition["exitClass"] != transition["result"].get("exitClass"):
            fail(f"{transition_path} has inconsistent exitClass values")
        result_errors = sorted(
            validator.iter_errors(transition["result"]),
            key=lambda error: list(error.path),
        )
        if result_errors:
            fail(
                f"{transition_path} result does not match schema: "
                f"{result_errors[0].message}"
            )

        for snapshot_name in ["initialSnapshot", "finalSnapshot"]:
            files = transition[snapshot_name].get("files")
            if not isinstance(files, list):
                fail(f"{transition_path} {snapshot_name} must contain files")
            paths = [file.get("path") for file in files]
            if paths != sorted(paths) or len(paths) != len(set(paths)):
                fail(f"{transition_path} {snapshot_name} paths are not canonical")
            for file in files:
                try:
                    content = bytes.fromhex(file["contentHex"])
                except (KeyError, ValueError):
                    fail(f"{transition_path} contains invalid contentHex")
                identity = file.get("contentIdentity", {})
                expected_hash = "sha256:" + hashlib.sha256(content).hexdigest()
                if identity.get("hash") != expected_hash:
                    fail(f"{transition_path} contains an invalid content hash")
                if identity.get("size") != len(content):
                    fail(f"{transition_path} contains an invalid content size")

    print("golden check passed")


if __name__ == "__main__":
    main()

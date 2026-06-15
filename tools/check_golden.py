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
TRANSITION_FIXTURE = (
    "golden/workspace-transitions/apply-title-replacement.json"
)
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

    transition = json.loads((ROOT / TRANSITION_FIXTURE).read_text())
    generated_transition = subprocess.run(
        [
            "dune",
            "exec",
            "--root",
            "sugar",
            "test/transition_fixture.exe",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    if json.loads(generated_transition.stdout) != transition:
        fail(f"{TRANSITION_FIXTURE} differs from the OCaml transition output")

    required_transition_fields = {
        "schemaVersion",
        "caseId",
        "initialSnapshot",
        "command",
        "result",
        "finalSnapshot",
        "exitClass",
    }
    if set(transition) != required_transition_fields:
        fail(f"{TRANSITION_FIXTURE} has an invalid top-level structure")
    if transition["schemaVersion"] != "1":
        fail(f"{TRANSITION_FIXTURE} has an unexpected schemaVersion")
    if transition["exitClass"] != transition["result"].get("exitClass"):
        fail(f"{TRANSITION_FIXTURE} has inconsistent exitClass values")
    result_errors = sorted(
        validator.iter_errors(transition["result"]),
        key=lambda error: list(error.path),
    )
    if result_errors:
        fail(
            f"{TRANSITION_FIXTURE} result does not match schema: "
            f"{result_errors[0].message}"
        )

    for snapshot_name in ["initialSnapshot", "finalSnapshot"]:
        files = transition[snapshot_name].get("files")
        if not isinstance(files, list):
            fail(f"{TRANSITION_FIXTURE} {snapshot_name} must contain files")
        paths = [file.get("path") for file in files]
        if paths != sorted(paths) or len(paths) != len(set(paths)):
            fail(f"{TRANSITION_FIXTURE} {snapshot_name} paths are not canonical")
        for file in files:
            try:
                content = bytes.fromhex(file["contentHex"])
            except (KeyError, ValueError):
                fail(f"{TRANSITION_FIXTURE} contains invalid contentHex")
            identity = file.get("contentIdentity", {})
            expected_hash = "sha256:" + hashlib.sha256(content).hexdigest()
            if identity.get("hash") != expected_hash:
                fail(f"{TRANSITION_FIXTURE} contains an invalid content hash")
            if identity.get("size") != len(content):
                fail(f"{TRANSITION_FIXTURE} contains an invalid content size")

    print("golden check passed")


if __name__ == "__main__":
    main()

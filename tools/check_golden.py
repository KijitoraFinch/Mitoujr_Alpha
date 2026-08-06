#!/usr/bin/env python3
"""Validate retained Phase 0 and Phase 1 golden outputs."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from copy import deepcopy
from pathlib import Path
from urllib.parse import unquote_to_bytes

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from json_contract import (
    ContractJsonError,
    equal_exact as json_equal_exact,
    load as strict_json_load,
    loads as strict_json_loads,
)
from semantic_contract import semantic_errors


ROOT = Path(__file__).resolve().parents[1]

INSPECT_GOLDEN = "golden/inspect/linking.expected.json"
RELATED_GOLDEN = "golden/related/linking.expected.json"
RELATED_TEXT_GOLDEN = "golden/related/linking.expected.txt"
READ_TEXT_GOLDEN = "golden/read/linking.expected.txt"
CHECK_GOLDEN = "golden/check/basic.expected.json"
DERIVE_GOLDEN = "golden/derive/linking-to-sidecar.expected.json"
MISSING_SIDECAR_DERIVE_GOLDEN = "golden/derive/missing-sidecar.expected.json"
RESOLVE_GOLDEN = "golden/resolve/latency-run-a.expected.json"
SCAN_GOLDEN = "golden/scan/basic.expected.json"
IGNORE_SCAN_GOLDEN = "golden/scan/ignore.expected.json"
APPLY_DRY_RUN_GOLDEN = "golden/cli/apply-dry-run.expected.json"
APPLY_INVALID_INPUT_GOLDEN = "golden/cli/apply-invalid-input.expected.json"
APPLY_IO_FAILURE_GOLDEN = "golden/cli/apply-io-failure.expected.json"
CAPABILITIES_GOLDEN = "golden/cli/capabilities.expected.json"
EXTENSION_TEST_GOLDEN = "golden/cli/extension-test.expected.json"
EXTENSION_TEST_UNSUPPORTED_GOLDEN = (
    "golden/cli/extension-test-unsupported-version.expected.json"
)
EXTENSION_DESCRIPTOR = "fixtures/extensions/valid-descriptor.json"
EXTENSION_UNSUPPORTED_DESCRIPTOR = (
    "fixtures/extensions/unsupported-version-descriptor.json"
)
PROTOCOL_INTEGER_CORPUS = "spec/protocol-integers.json"
UTF8_CORPUS = "spec/utf8.json"

NORMAL_FORM_FIXTURE = "golden/normal-form/representative.command-result.json"
OBSERVATION_FIXTURE = "golden/normal-form/inspect-observations.command-result.json"
TRANSITION_FIXTURES = {
    "golden/workspace-transitions/apply-title-replacement.json": "apply-title-replacement",
    "golden/workspace-transitions/apply-identity-mismatch.json": "apply-identity-mismatch",
    "golden/workspace-transitions/apply-range-out-of-bounds.json": "apply-range-out-of-bounds",
    "golden/workspace-transitions/apply-overlap.json": "apply-overlap",
    "golden/workspace-transitions/apply-result-identity-mismatch.json": "apply-result-identity-mismatch",
    "golden/workspace-transitions/apply-repeated-no-op.json": "apply-repeated-no-op",
}
COMMAND_RESULT_SCHEMA = "schemas/command-result.schema.json"
STANDALONE_SCHEMA_SAMPLES = {
    "schemas/diagnostic.schema.json": lambda fixture, _scan, _observation: fixture[
        "diagnostics"
    ][0],
    "schemas/patch.schema.json": lambda fixture, _scan, _observation: fixture[
        "diagnostics"
    ][0][
        "suggestedFixes"
    ][0],
    "schemas/snapshot.schema.json": lambda fixture, _scan, _observation: fixture[
        "snapshots"
    ][0],
    "schemas/artifact.schema.json": lambda _fixture, scan, _observation: scan[
        "artifacts"
    ][0],
    "schemas/region.schema.json": lambda _fixture, _scan, observation: observation[
        "regions"
    ][0],
    "schemas/reference.schema.json": lambda _fixture, _scan, observation: observation[
        "references"
    ][0],
    "schemas/annotation.schema.json": lambda _fixture, _scan, observation: observation[
        "annotations"
    ][0],
}
PROCESS_EXIT_CODES = {
    "success": 0,
    "diagnostic-error": 1,
    "usage-error": 2,
    "internal-error": 3,
}


def fail(message: str) -> None:
    print(f"golden check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: str):
    try:
        return strict_json_load(ROOT / path, display_path=path)
    except ContractJsonError as error:
        fail(str(error))


def generated_json(text: str, source: str):
    try:
        return strict_json_loads(text, source=source)
    except ContractJsonError as error:
        fail(str(error))


def require_process_exit(
    process: subprocess.CompletedProcess[str], expected: int, source: str
) -> None:
    if process.returncode != expected:
        fail(
            f"{source} exited {process.returncode}, expected {expected}; "
            f"stdout={process.stdout!r}; stderr={process.stderr!r}"
        )


def require_process_success(
    process: subprocess.CompletedProcess[str], source: str
) -> None:
    require_process_exit(process, 0, source)


def require_cli_scan(expected, golden: str, workspace: str) -> None:
    generated = subprocess.run(
        [
            "dune",
            "exec",
            "--root",
            "sugar",
            "bin/main.exe",
            "--",
            "scan",
            "--workspace",
            workspace,
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require_process_success(generated, f"monika scan {workspace}")
    actual = generated_json(generated.stdout, f"monika scan {workspace} stdout")
    if not json_equal_exact(actual, expected):
        fail(f"{golden} differs from the OCaml scan output")


def require_semantically_valid(result, source: str) -> None:
    errors = semantic_errors(result)
    if errors:
        fail(f"{source} violates semantic constraints: {errors[0]}")


def native_workspace_path(workspace: Path, canonical_path: str) -> Path:
    result = workspace
    for segment in canonical_path.split("/"):
        try:
            native_segment = unquote_to_bytes(segment).decode("utf-8")
        except UnicodeError as error:
            fail(
                "CLI end-to-end fixtures currently require UTF-8 workspace paths: "
                f"{canonical_path!r}: {error}"
            )
        result /= native_segment
    return result


def materialize_snapshot(workspace: Path, snapshot) -> None:
    for file in snapshot["files"]:
        path = native_workspace_path(workspace, file["path"])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(bytes.fromhex(file["contentHex"]))


def require_snapshot(workspace: Path, snapshot, source: str) -> None:
    expected = {
        file["path"]: bytes.fromhex(file["contentHex"])
        for file in snapshot["files"]
    }
    for canonical_path, content in expected.items():
        path = native_workspace_path(workspace, canonical_path)
        if not path.is_file():
            fail(f"{source} did not produce expected file: {canonical_path}")
        if path.read_bytes() != content:
            fail(f"{source} produced unexpected bytes: {canonical_path}")


def require_cli_apply_transition(transition, source: str) -> None:
    with tempfile.TemporaryDirectory(prefix="monika-apply-golden-") as temporary:
        temporary_root = Path(temporary)
        workspace = temporary_root / "workspace"
        workspace.mkdir()
        materialize_snapshot(workspace, transition["initialSnapshot"])
        patch_path = temporary_root / "patch.json"
        patch_path.write_text(
            json.dumps(
                transition["command"]["patch"],
                ensure_ascii=False,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        completed = subprocess.run(
            [
                str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
                "apply",
                "--workspace",
                str(workspace),
                "--patch",
                str(patch_path),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        expected_exit_code = PROCESS_EXIT_CODES[transition["exitClass"]]
        require_process_exit(completed, expected_exit_code, f"{source} CLI")
        if completed.stderr:
            fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
        result = generated_json(completed.stdout, f"{source} CLI stdout")
        if not json_equal_exact(result, transition["result"]):
            fail(f"{source} CLI stdout differs from the golden result")
        require_snapshot(workspace, transition["finalSnapshot"], source)


def require_cli_apply_dry_run(transition, expected, source: str) -> None:
    with tempfile.TemporaryDirectory(prefix="monika-apply-dry-run-") as temporary:
        temporary_root = Path(temporary)
        workspace = temporary_root / "workspace"
        workspace.mkdir()
        materialize_snapshot(workspace, transition["initialSnapshot"])
        patch_path = temporary_root / "patch.json"
        patch_path.write_text(
            json.dumps(
                transition["command"]["patch"],
                ensure_ascii=False,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        completed = subprocess.run(
            [
                str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
                "apply",
                "--workspace",
                str(workspace),
                "--patch",
                str(patch_path),
                "--dry-run",
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        require_process_exit(
            completed,
            PROCESS_EXIT_CODES[expected["exitClass"]],
            f"{source} CLI",
        )
        if completed.stderr:
            fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
        result = generated_json(completed.stdout, f"{source} CLI stdout")
        if not json_equal_exact(result, expected):
            fail(f"{source} CLI stdout differs from the golden result")
        require_snapshot(workspace, transition["initialSnapshot"], source)


def require_cli_apply_invalid_input(expected, source: str) -> None:
    completed = subprocess.run(
        [
            str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
            "apply",
            "--patch",
            "unused.json",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require_process_exit(
        completed,
        PROCESS_EXIT_CODES[expected["exitClass"]],
        f"{source} CLI",
    )
    if completed.stderr:
        fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
    result = generated_json(completed.stdout, f"{source} CLI stdout")
    if not json_equal_exact(result, expected):
        fail(f"{source} CLI stdout differs from the golden result")


def require_cli_apply_io_failure(transition, expected, source: str) -> None:
    with tempfile.TemporaryDirectory(prefix="monika-apply-io-golden-") as temporary:
        temporary_root = Path(temporary)
        workspace = temporary_root / "workspace"
        workspace.mkdir()
        materialize_snapshot(workspace, transition["initialSnapshot"])
        patch_path = temporary_root / "patch.json"
        patch_path.write_text(
            json.dumps(
                transition["command"]["patch"],
                ensure_ascii=False,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        missing_temp = temporary_root / "missing-system-temp"
        environment = os.environ.copy()
        for name in ("TMPDIR", "TMP", "TEMP"):
            environment[name] = str(missing_temp)
        completed = subprocess.run(
            [
                str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
                "apply",
                "--workspace",
                str(workspace),
                "--patch",
                str(patch_path),
            ],
            cwd=ROOT,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )
        require_process_exit(
            completed,
            PROCESS_EXIT_CODES[expected["exitClass"]],
            f"{source} CLI",
        )
        if completed.stderr:
            fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
        result = generated_json(completed.stdout, f"{source} CLI stdout")
        if not json_equal_exact(result, expected):
            fail(f"{source} CLI stdout differs from the golden result")
        require_snapshot(workspace, transition["initialSnapshot"], source)


def require_cli_inspect(expected, source: str) -> None:
    completed = subprocess.run(
        [
            str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
            "inspect",
            "--workspace",
            str(ROOT / "fixtures" / "basic"),
            "--artifact",
            "docs/linking.md",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require_process_exit(
        completed,
        PROCESS_EXIT_CODES[expected["exitClass"]],
        f"{source} CLI",
    )
    if completed.stderr:
        fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
    result = generated_json(completed.stdout, f"{source} CLI stdout")
    if not json_equal_exact(result, expected):
        fail(f"{source} differs from the OCaml inspect output")


def require_cli_related(expected, source: str) -> None:
    completed = subprocess.run(
        [
            str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
            "related",
            "--workspace",
            str(ROOT / "fixtures" / "basic"),
            "--artifact",
            "docs/linking.md",
            "--json",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require_process_success(completed, f"{source} CLI")
    if completed.stderr:
        fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
    result = generated_json(completed.stdout, f"{source} CLI stdout")
    if not json_equal_exact(result, expected):
        fail(f"{source} differs from the OCaml related output")

    text_completed = subprocess.run(
        [
            str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
            "related",
            "--workspace",
            str(ROOT / "fixtures" / "basic"),
            "--artifact",
            "docs/linking.md",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require_process_success(text_completed, f"{RELATED_TEXT_GOLDEN} CLI")
    if text_completed.stderr:
        fail(
            f"{RELATED_TEXT_GOLDEN} CLI wrote unexpected stderr: "
            f"{text_completed.stderr!r}"
        )
    expected_text = (ROOT / RELATED_TEXT_GOLDEN).read_text(encoding="utf-8")
    if text_completed.stdout != expected_text:
        fail(f"{RELATED_TEXT_GOLDEN} differs from the OCaml related text output")


def require_cli_read() -> None:
    completed = subprocess.run(
        [
            str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
            "read",
            "--workspace",
            str(ROOT / "fixtures" / "basic"),
            "--artifact",
            "docs/linking.md",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require_process_success(completed, f"{READ_TEXT_GOLDEN} CLI")
    if completed.stderr:
        fail(
            f"{READ_TEXT_GOLDEN} CLI wrote unexpected stderr: "
            f"{completed.stderr!r}"
        )
    expected = (ROOT / READ_TEXT_GOLDEN).read_text(encoding="utf-8")
    if completed.stdout != expected:
        fail(f"{READ_TEXT_GOLDEN} differs from the OCaml read output")


def require_agent_cli_failures() -> None:
    cases = [
        (
            [
                "related",
                "--workspace",
                str(ROOT / "fixtures" / "basic"),
                "--artifact",
                "docs/linking.md",
                "--limit",
                "0",
            ],
            2,
            "monika related: --limit must be a positive integer\n",
        ),
        (
            [
                "related",
                "--workspace",
                str(ROOT / "fixtures" / "basic"),
                "--artifact",
                "missing.md",
            ],
            2,
            "monika related: artifact does not exist\n",
        ),
        (
            [
                "read",
                "--workspace",
                str(ROOT / "fixtures" / "basic"),
                "--artifact",
                "runs/metrics.jsonl",
            ],
            1,
            (
                "monika read: unsupported-artifact: "
                "no standard interpreter supports this artifact\n"
            ),
        ),
    ]
    executable = str(
        ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"
    )
    for arguments, expected_exit, expected_stderr in cases:
        completed = subprocess.run(
            [executable, *arguments],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        require_process_exit(
            completed,
            expected_exit,
            f"{arguments[0]} failure case",
        )
        if completed.stdout:
            fail(f"{arguments[0]} failure case wrote unexpected stdout")
        if completed.stderr != expected_stderr:
            fail(f"{arguments[0]} failure case wrote unexpected stderr")


def require_cli_check(expected, source: str) -> None:
    completed = subprocess.run(
        [
            str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
            "check",
            "--workspace",
            str(ROOT / "fixtures" / "basic"),
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require_process_exit(
        completed,
        PROCESS_EXIT_CODES[expected["exitClass"]],
        f"{source} CLI",
    )
    if completed.stderr:
        fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
    result = generated_json(completed.stdout, f"{source} CLI stdout")
    if not json_equal_exact(result, expected):
        fail(f"{source} differs from the OCaml check output")


def run_cli_derive(workspace: Path, source: str):
    completed = subprocess.run(
        [
            str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
            "derive",
            "--workspace",
            str(workspace),
            "--artifact",
            "docs/linking.md",
            "--target",
            "sidecar",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != PROCESS_EXIT_CODES[
        generated_json(completed.stdout, f"{source} CLI stdout")["exitClass"]
    ]:
        fail(f"{source} CLI returned an exit code inconsistent with its result")
    if completed.stderr:
        fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
    return generated_json(completed.stdout, f"{source} CLI stdout")


def require_cli_derive(expected, source: str) -> None:
    result = run_cli_derive(ROOT / "fixtures" / "basic", source)
    if not json_equal_exact(result, expected):
        fail(f"{source} differs from the OCaml derive output")


def require_derive_apply_idempotency(source: str) -> None:
    with tempfile.TemporaryDirectory(prefix="monika-derive-golden-") as temporary:
        workspace = Path(temporary) / "workspace"
        shutil.copytree(ROOT / "fixtures" / "basic", workspace)
        derived = run_cli_derive(workspace, source)
        if len(derived.get("patches", [])) != 1:
            fail(f"{source} must propose exactly one initial patch")
        patch_path = Path(temporary) / "patch.json"
        patch_path.write_text(
            json.dumps(derived["patches"][0], ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        applied = subprocess.run(
            [
                str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
                "apply",
                "--workspace",
                str(workspace),
                "--patch",
                str(patch_path),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        if applied.returncode != 0 or applied.stderr:
            fail(f"{source} generated patch did not apply successfully")
        applied_result = generated_json(applied.stdout, f"{source} apply stdout")
        require_semantically_valid(applied_result, f"{source} applied result")
        repeated = run_cli_derive(workspace, f"{source} repeated derive")
        if repeated.get("patches") != [] or repeated.get("status") != "ok":
            diagnostics = [
                (
                    diagnostic.get("code"),
                    diagnostic.get("message"),
                )
                for diagnostic in repeated.get("diagnostics", [])
            ]
            fail(
                f"{source} derive -> apply -> derive is not idempotent: "
                f"status={repeated.get('status')!r}, diagnostics={diagnostics!r}, "
                f"patches={len(repeated.get('patches', []))}"
            )

def require_missing_sidecar_create(expected, source: str) -> None:
    with tempfile.TemporaryDirectory(
        prefix="monika-missing-sidecar-golden-"
    ) as temporary:
        temporary_root = Path(temporary)
        workspace = temporary_root / "workspace"
        shutil.copytree(ROOT / "fixtures" / "basic", workspace)
        (workspace / "docs" / "linking.annotations.yaml").unlink()
        derived = run_cli_derive(workspace, source)
        if not json_equal_exact(derived, expected):
            fail(f"{source} differs from the missing-sidecar derive output")
        result_path = temporary_root / "derive-result.json"
        result_path.write_text(
            json.dumps(derived, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        multiple = deepcopy(derived)
        alternate = deepcopy(derived["patches"][0])
        alternate["id"] = "patch:alternate-create"
        multiple["patches"].append(alternate)
        multiple_path = temporary_root / "multiple-patches-result.json"
        multiple_path.write_text(
            json.dumps(multiple, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        ambiguous = subprocess.run(
            [
                str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
                "apply",
                "--workspace",
                str(workspace),
                "--result",
                str(multiple_path),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        ambiguous_result = generated_json(
            ambiguous.stdout, f"{source} ambiguous apply --result stdout"
        )
        if ambiguous.returncode != 2 or ambiguous_result.get("status") != "invalid-input":
            fail(f"{source} accepts multiple result patches without --patch-id")
        selected = subprocess.run(
            [
                str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
                "apply",
                "--workspace",
                str(workspace),
                "--result",
                str(multiple_path),
                "--patch-id",
                derived["patches"][0]["id"],
                "--dry-run",
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        selected_result = generated_json(
            selected.stdout, f"{source} selected apply --result stdout"
        )
        if selected.returncode != 0 or selected_result.get("status") != "patches-proposed":
            fail(f"{source} could not select a result patch by ID")
        applied = subprocess.run(
            [
                str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
                "apply",
                "--workspace",
                str(workspace),
                "--result",
                str(result_path),
            ],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        if applied.returncode != 0 or applied.stderr:
            fail(f"{source} create patch did not apply through --result")
        applied_result = generated_json(
            applied.stdout, f"{source} apply --result stdout"
        )
        require_semantically_valid(applied_result, f"{source} applied result")
        if applied_result.get("status") != "applied":
            fail(f"{source} create patch did not report applied")
        changed = applied_result.get("changedArtifacts", [])
        if len(changed) != 1 or "before" in changed[0]:
            fail(f"{source} create result must omit the absent before identity")
        repeated = run_cli_derive(workspace, f"{source} repeated derive")
        if repeated.get("status") != "ok" or repeated.get("patches") != []:
            fail(f"{source} create derive -> apply -> derive is not idempotent")


def require_cli_resolve(expected, source: str) -> None:
    completed = subprocess.run(
        [
            str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
            "resolve",
            "--workspace",
            str(ROOT / "fixtures" / "basic"),
            "--artifact",
            "docs/linking.md",
            "--reference",
            "latency-run-a",
            "--observed-at",
            "2026-07-17T00:00:00Z",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require_process_exit(
        completed,
        PROCESS_EXIT_CODES[expected["exitClass"]],
        f"{source} CLI",
    )
    if completed.stderr:
        fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
    result = generated_json(completed.stdout, f"{source} CLI stdout")
    if not json_equal_exact(result, expected):
        fail(f"{source} differs from the OCaml resolve output")


def require_cli_capabilities(expected, source: str) -> None:
    completed = subprocess.run(
        [
            str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
            "capabilities",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require_process_exit(
        completed,
        PROCESS_EXIT_CODES[expected["exitClass"]],
        f"{source} CLI",
    )
    if completed.stderr:
        fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
    result = generated_json(completed.stdout, f"{source} CLI stdout")
    if not json_equal_exact(result, expected):
        fail(f"{source} differs from the OCaml capabilities output")


def require_cli_extension_test(expected, descriptor: str, source: str) -> None:
    completed = subprocess.run(
        [
            str(ROOT / "sugar" / "_build" / "default" / "bin" / "main.exe"),
            "extension",
            "test",
            "--descriptor",
            str(ROOT / descriptor),
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    require_process_exit(
        completed,
        PROCESS_EXIT_CODES[expected["exitClass"]],
        f"{source} CLI",
    )
    if completed.stderr:
        fail(f"{source} CLI wrote unexpected stderr: {completed.stderr!r}")
    result = generated_json(completed.stdout, f"{source} CLI stdout")
    if not json_equal_exact(result, expected):
        fail(f"{source} differs from the OCaml extension test output")


def main() -> None:
    schema_documents = {
        path.relative_to(ROOT).as_posix(): read_json(path.relative_to(ROOT).as_posix())
        for path in sorted((ROOT / "schemas").glob("*.schema.json"))
    }
    for path, schema in schema_documents.items():
        try:
            Draft202012Validator.check_schema(schema)
        except Exception as error:
            fail(f"{path} is not a valid Draft 2020-12 schema: {error}")
    registry = Registry().with_resources(
        (
            schema["$id"],
            Resource.from_contents(schema),
        )
        for schema in schema_documents.values()
    )
    schema_data = schema_documents[COMMAND_RESULT_SCHEMA]
    validator = Draft202012Validator(schema_data, registry=registry)
    path_validator = Draft202012Validator(schema_data["$defs"]["path"])
    identity_validator = Draft202012Validator(
        schema_data["$defs"]["contentIdentity"]
    )
    patch_validator = Draft202012Validator(
        schema_documents["schemas/patch.schema.json"], registry=registry
    )
    signed_integer_validator = Draft202012Validator(
        schema_data["$defs"]["selector"]["oneOf"][3]["properties"]["where"][
            "additionalProperties"
        ]["oneOf"][1]
    )
    nonnegative_integer_validator = Draft202012Validator(
        schema_data["$defs"]["contentIdentity"]["properties"]["size"]
    )
    for case in read_json(PROTOCOL_INTEGER_CORPUS):
        validator_for_domain = {
            "signed": signed_integer_validator,
            "nonnegative": nonnegative_integer_validator,
        }.get(case.get("domain"))
        if validator_for_domain is None:
            fail(f"{PROTOCOL_INTEGER_CORPUS} has an unknown domain: {case!r}")
        actual = validator_for_domain.is_valid(case.get("value"))
        if actual is not case.get("valid"):
            fail(
                f"{PROTOCOL_INTEGER_CORPUS} case {case.get('id')!r} "
                "has an unexpected schema classification"
            )
    subprocess.run(
        [
            "dune",
            "exec",
            "--root",
            "sugar",
            "test/test_protocol_integers.exe",
            str(ROOT / PROTOCOL_INTEGER_CORPUS),
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    for case in read_json(UTF8_CORPUS):
        try:
            bytes.fromhex(case["hex"]).decode("utf-8")
            actual = True
        except UnicodeDecodeError:
            actual = False
        if actual is not case.get("valid"):
            fail(
                f"{UTF8_CORPUS} case {case.get('id')!r} has an unexpected "
                "specification-validator classification"
            )
    subprocess.run(
        [
            "dune",
            "exec",
            "--root",
            "sugar",
            "test/test_utf8.exe",
            str(ROOT / UTF8_CORPUS),
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    fixture = read_json(NORMAL_FORM_FIXTURE)
    observation_fixture = read_json(OBSERVATION_FIXTURE)
    errors = sorted(validator.iter_errors(fixture), key=lambda error: list(error.path))
    if errors:
        fail(f"{NORMAL_FORM_FIXTURE} does not match schema: {errors[0].message}")
    require_semantically_valid(fixture, NORMAL_FORM_FIXTURE)

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
    if not json_equal_exact(
        generated_json(generated.stdout, "normal_fixture.exe stdout"), fixture
    ):
        fail(f"{NORMAL_FORM_FIXTURE} differs from the OCaml encoder output")

    observation_errors = sorted(
        validator.iter_errors(observation_fixture),
        key=lambda error: list(error.path),
    )
    if observation_errors:
        fail(
            f"{OBSERVATION_FIXTURE} does not match schema: "
            f"{observation_errors[0].message}"
        )
    require_semantically_valid(observation_fixture, OBSERVATION_FIXTURE)
    generated_observation = subprocess.run(
        [
            "dune",
            "exec",
            "--root",
            "sugar",
            "test/observation_fixture.exe",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    if not json_equal_exact(
        generated_json(
            generated_observation.stdout, "observation_fixture.exe stdout"
        ),
        observation_fixture,
    ):
        fail(f"{OBSERVATION_FIXTURE} differs from the OCaml encoder output")

    for required_collection in [
        "diagnostics",
        "patches",
        "changedArtifacts",
        "conflicts",
        "snapshots",
        "artifacts",
        "regions",
        "references",
        "annotations",
        "capabilities",
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

    edit_patch = fixture["diagnostics"][0]["suggestedFixes"][0]
    invalid = deepcopy(edit_patch)
    invalid["content"] = "not valid on edit"
    if patch_validator.is_valid(invalid):
        fail("schema accepts create content on an edit patch")

    create_patch = deepcopy(edit_patch)
    create_patch["operation"] = "create"
    del create_patch["expectedContentIdentity"]
    del create_patch["edits"]
    create_patch["content"] = "Heading\n"
    if not patch_validator.is_valid(create_patch):
        fail("schema rejects a structurally valid create patch")
    invalid = deepcopy(create_patch)
    invalid["edits"] = []
    if patch_validator.is_valid(invalid):
        fail("schema accepts edits on a create patch")
    invalid = deepcopy(create_patch)
    del invalid["content"]
    if patch_validator.is_valid(invalid):
        fail("schema accepts a create patch without content")

    invalid = deepcopy(fixture)
    invalid["conflicts"][0]["expected"]["hash"] += "\n"
    if validator.is_valid(invalid):
        fail("schema accepts a content hash with trailing data")

    invalid = deepcopy(fixture)
    invalid["diagnostics"][0]["location"]["range"] = {"start": 5, "end": 0}
    if not semantic_errors(invalid):
        fail("semantic validator accepts a range whose end precedes its start")

    for invalid_integer in [9007199254740992, -1]:
        invalid = deepcopy(fixture)
        invalid["summary"]["conflicts"] = invalid_integer
        if validator.is_valid(invalid):
            fail(f"schema accepts invalid summary count: {invalid_integer}")

    invalid = deepcopy(fixture)
    invalid["snapshots"][0]["target"]["selector"]["where"]["attempt"] = (
        9007199254740992
    )
    if validator.is_valid(invalid):
        fail("schema accepts row-filter integer above the safe-integer range")

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
    invalid["exitClass"] = "success"
    if validator.is_valid(invalid):
        fail("schema accepts success exitClass for a conflict result")

    invalid = deepcopy(fixture)
    invalid["diagnostics"][0]["defaultSeverity"] = "warning"
    if validator.is_valid(invalid):
        fail("schema accepts a default severity that disagrees with the code registry")

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

    valid = deepcopy(fixture)
    valid["status"] = "applied"
    valid["exitClass"] = "success"
    valid["conflicts"] = []
    valid["diagnostics"] = []
    valid["changedArtifacts"] = [
        {
            "path": "docs/new.txt",
            "after": {
                "hash": "sha256:b5e07ae6610ae6dd33f1903bea1a87e0e874347512063488bd428b4259c0e3f1",
                "size": 8,
            },
        }
    ]
    if not validator.is_valid(valid):
        fail("schema rejects a created changed artifact without before")

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
        "kind": "artifact-already-exists",
        "patchId": "patch:readme-title",
        "target": "docs/README%20%FF.md",
        "actual": {
            "hash": "sha256:c26f241ab13a3f83ef4883430a67cccf205b31ad5a7e8493b703830d3426b08a",
            "size": 8,
        },
    }
    if not validator.is_valid(valid):
        fail("schema rejects artifact-already-exists conflict")

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
    invalid["snapshots"][0]["target"].pop("selector")
    if validator.is_valid(invalid):
        fail("schema accepts a resolution target without a selector")

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
        "docs/name\n",
        "docs/name\r",
        "docs/name\u2028",
        "docs/name\u2029",
    ]:
        invalid = deepcopy(fixture)
        invalid["conflicts"][0]["target"] = path
        if validator.is_valid(invalid):
            fail(f"schema accepts non-canonical workspace path: {path!r}")

    scan_fixture = read_json(SCAN_GOLDEN)
    scan_errors = sorted(
        validator.iter_errors(scan_fixture), key=lambda error: list(error.path)
    )
    if scan_errors:
        fail(f"{SCAN_GOLDEN} does not match schema: {scan_errors[0].message}")
    require_semantically_valid(scan_fixture, SCAN_GOLDEN)

    ignore_scan_fixture = read_json(IGNORE_SCAN_GOLDEN)
    ignore_scan_errors = sorted(
        validator.iter_errors(ignore_scan_fixture),
        key=lambda error: list(error.path),
    )
    if ignore_scan_errors:
        fail(
            f"{IGNORE_SCAN_GOLDEN} does not match schema: "
            f"{ignore_scan_errors[0].message}"
        )
    require_semantically_valid(ignore_scan_fixture, IGNORE_SCAN_GOLDEN)

    inspect_fixture = read_json(INSPECT_GOLDEN)
    inspect_errors = sorted(
        validator.iter_errors(inspect_fixture), key=lambda error: list(error.path)
    )
    if inspect_errors:
        fail(f"{INSPECT_GOLDEN} does not match schema: {inspect_errors[0].message}")
    require_semantically_valid(inspect_fixture, INSPECT_GOLDEN)

    related_fixture = read_json(RELATED_GOLDEN)
    related_validator = Draft202012Validator(
        schema_documents["schemas/related-result.schema.json"],
        registry=registry,
    )
    related_errors = sorted(
        related_validator.iter_errors(related_fixture),
        key=lambda error: list(error.path),
    )
    if related_errors:
        fail(
            f"{RELATED_GOLDEN} does not match schema: "
            f"{related_errors[0].message}"
        )
    related_coverage = related_fixture["coverage"]
    expected_complete = (
        related_coverage["unsupportedArtifacts"] == 0
        and related_coverage["failedArtifacts"] == 0
    )
    if related_coverage["complete"] is not expected_complete:
        fail(f"{RELATED_GOLDEN} has an inconsistent coverage completeness claim")

    check_fixture = read_json(CHECK_GOLDEN)
    check_errors = sorted(
        validator.iter_errors(check_fixture), key=lambda error: list(error.path)
    )
    if check_errors:
        fail(f"{CHECK_GOLDEN} does not match schema: {check_errors[0].message}")
    require_semantically_valid(check_fixture, CHECK_GOLDEN)

    derive_fixture = read_json(DERIVE_GOLDEN)
    derive_errors = sorted(
        validator.iter_errors(derive_fixture), key=lambda error: list(error.path)
    )
    if derive_errors:
        fail(f"{DERIVE_GOLDEN} does not match schema: {derive_errors[0].message}")
    require_semantically_valid(derive_fixture, DERIVE_GOLDEN)

    missing_sidecar_derive_fixture = read_json(MISSING_SIDECAR_DERIVE_GOLDEN)
    missing_sidecar_derive_errors = sorted(
        validator.iter_errors(missing_sidecar_derive_fixture),
        key=lambda error: list(error.path),
    )
    if missing_sidecar_derive_errors:
        fail(
            f"{MISSING_SIDECAR_DERIVE_GOLDEN} does not match schema: "
            f"{missing_sidecar_derive_errors[0].message}"
        )
    require_semantically_valid(
        missing_sidecar_derive_fixture, MISSING_SIDECAR_DERIVE_GOLDEN
    )

    resolve_fixture = read_json(RESOLVE_GOLDEN)
    resolve_errors = sorted(
        validator.iter_errors(resolve_fixture), key=lambda error: list(error.path)
    )
    if resolve_errors:
        fail(f"{RESOLVE_GOLDEN} does not match schema: {resolve_errors[0].message}")
    require_semantically_valid(resolve_fixture, RESOLVE_GOLDEN)

    capabilities_fixture = read_json(CAPABILITIES_GOLDEN)
    capabilities_errors = sorted(
        validator.iter_errors(capabilities_fixture),
        key=lambda error: list(error.path),
    )
    if capabilities_errors:
        fail(
            f"{CAPABILITIES_GOLDEN} does not match schema: "
            f"{capabilities_errors[0].message}"
        )
    require_semantically_valid(capabilities_fixture, CAPABILITIES_GOLDEN)

    extension_test_fixture = read_json(EXTENSION_TEST_GOLDEN)
    extension_test_errors = sorted(
        validator.iter_errors(extension_test_fixture),
        key=lambda error: list(error.path),
    )
    if extension_test_errors:
        fail(
            f"{EXTENSION_TEST_GOLDEN} does not match schema: "
            f"{extension_test_errors[0].message}"
        )
    require_semantically_valid(extension_test_fixture, EXTENSION_TEST_GOLDEN)

    extension_unsupported_fixture = read_json(EXTENSION_TEST_UNSUPPORTED_GOLDEN)
    extension_unsupported_errors = sorted(
        validator.iter_errors(extension_unsupported_fixture),
        key=lambda error: list(error.path),
    )
    if extension_unsupported_errors:
        fail(
            f"{EXTENSION_TEST_UNSUPPORTED_GOLDEN} does not match schema: "
            f"{extension_unsupported_errors[0].message}"
        )
    require_semantically_valid(
        extension_unsupported_fixture, EXTENSION_TEST_UNSUPPORTED_GOLDEN
    )

    for schema_path, sample in STANDALONE_SCHEMA_SAMPLES.items():
        standalone = Draft202012Validator(
            schema_documents[schema_path], registry=registry
        )
        errors = sorted(
            standalone.iter_errors(
                sample(fixture, scan_fixture, observation_fixture)
            ),
            key=lambda error: list(error.path),
        )
        if errors:
            fail(f"sample does not match {schema_path}: {errors[0].message}")

    capability_validator = Draft202012Validator(
        schema_documents["schemas/capability.schema.json"], registry=registry
    )
    capability_errors = sorted(
        capability_validator.iter_errors(capabilities_fixture["capabilities"][0]),
        key=lambda error: list(error.path),
    )
    if capability_errors:
        fail(
            "capabilities sample does not match schemas/capability.schema.json: "
            f"{capability_errors[0].message}"
        )

    extension_descriptor_validator = Draft202012Validator(
        schema_documents["schemas/extension-descriptor.schema.json"],
        registry=registry,
    )
    descriptor_errors = sorted(
        extension_descriptor_validator.iter_errors(read_json(EXTENSION_DESCRIPTOR)),
        key=lambda error: list(error.path),
    )
    if descriptor_errors:
        fail(
            f"{EXTENSION_DESCRIPTOR} does not match extension descriptor schema: "
            f"{descriptor_errors[0].message}"
        )
    if extension_descriptor_validator.is_valid(
        read_json(EXTENSION_UNSUPPORTED_DESCRIPTOR)
    ):
        fail("extension descriptor schema accepts an unsupported protocol version")

    invalid = deepcopy(capabilities_fixture)
    invalid["capabilities"].append(deepcopy(invalid["capabilities"][0]))
    if not semantic_errors(invalid):
        fail("semantic validation accepts duplicate capability identities")

    invalid = deepcopy(scan_fixture)
    invalid["exitClass"] = "diagnostic-error"
    if validator.is_valid(invalid):
        fail("schema accepts diagnostic-error exitClass for an ok result")

    warning_result = deepcopy(scan_fixture)
    warning_result["status"] = "diagnostics-found"
    warning_result["diagnostics"] = [deepcopy(fixture["diagnostics"][0])]
    warning_result["diagnostics"][0]["effectiveSeverity"] = "warning"
    warning_result["exitClass"] = "success"
    if not validator.is_valid(warning_result):
        fail("schema rejects a successful result containing only warning diagnostics")

    error_result = deepcopy(warning_result)
    error_result["diagnostics"][0]["effectiveSeverity"] = "error"
    error_result["exitClass"] = "diagnostic-error"
    if not validator.is_valid(error_result):
        fail("schema rejects diagnostic-error for an effective error diagnostic")
    invalid = deepcopy(error_result)
    invalid["exitClass"] = "success"
    if validator.is_valid(invalid):
        fail("schema accepts success exitClass for an effective error diagnostic")

    for status, exit_class in [
        ("invalid-input", "usage-error"),
        ("internal-error", "internal-error"),
    ]:
        result = deepcopy(scan_fixture)
        result["status"] = status
        result["artifacts"] = []
        result["summary"] = {"message": status}
        result["exitClass"] = exit_class
        if not validator.is_valid(result):
            fail(f"schema rejects the canonical exitClass for {status}")
        result["exitClass"] = "success"
        if validator.is_valid(result):
            fail(f"schema accepts success exitClass for {status}")
    require_cli_scan(scan_fixture, SCAN_GOLDEN, "fixtures/basic")
    require_cli_scan(ignore_scan_fixture, IGNORE_SCAN_GOLDEN, "fixtures/ignore")
    require_cli_inspect(inspect_fixture, INSPECT_GOLDEN)
    require_cli_related(related_fixture, RELATED_GOLDEN)
    require_cli_read()
    require_agent_cli_failures()
    require_cli_check(check_fixture, CHECK_GOLDEN)
    require_cli_derive(derive_fixture, DERIVE_GOLDEN)
    require_derive_apply_idempotency(DERIVE_GOLDEN)
    require_missing_sidecar_create(
        missing_sidecar_derive_fixture, MISSING_SIDECAR_DERIVE_GOLDEN
    )
    require_cli_resolve(resolve_fixture, RESOLVE_GOLDEN)
    require_cli_capabilities(capabilities_fixture, CAPABILITIES_GOLDEN)
    require_cli_extension_test(
        extension_test_fixture, EXTENSION_DESCRIPTOR, EXTENSION_TEST_GOLDEN
    )
    require_cli_extension_test(
        extension_unsupported_fixture,
        EXTENSION_UNSUPPORTED_DESCRIPTOR,
        EXTENSION_TEST_UNSUPPORTED_GOLDEN,
    )

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
        transition = read_json(transition_path)
        require_semantically_valid(transition, transition_path)
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
        if not json_equal_exact(
            generated_json(
                generated_transition.stdout,
                f"transition_fixture.exe {case_id} stdout",
            ),
            transition,
        ):
            fail(f"{transition_path} differs from the OCaml transition output")

        if set(transition) != required_transition_fields:
            fail(f"{transition_path} has an invalid top-level structure")
        if transition["schemaVersion"] != "6":
            fail(f"{transition_path} has an unexpected schemaVersion")
        if transition["caseId"] != case_id:
            fail(f"{transition_path} has unexpected caseId")
        command = transition["command"]
        if (
            not isinstance(command, dict)
            or set(command) != {"name", "patch"}
            or command["name"] != "apply"
        ):
            fail(f"{transition_path} has an invalid command")
        patch_errors = sorted(
            patch_validator.iter_errors(command["patch"]),
            key=lambda error: list(error.path),
        )
        if patch_errors:
            fail(
                f"{transition_path} patch does not match schema: "
                f"{patch_errors[0].message}"
            )
        require_semantically_valid(
            {"patches": [command["patch"]]}, f"{transition_path} command patch"
        )
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
        require_semantically_valid(transition["result"], transition_path)

        require_cli_apply_transition(transition, transition_path)

        for snapshot_name in ["initialSnapshot", "finalSnapshot"]:
            snapshot = transition[snapshot_name]
            if not isinstance(snapshot, dict) or set(snapshot) != {"files"}:
                fail(f"{transition_path} {snapshot_name} has an invalid structure")
            files = snapshot.get("files")
            if not isinstance(files, list):
                fail(f"{transition_path} {snapshot_name} must contain files")
            expected_file_fields = {"path", "contentHex", "contentIdentity"}
            if any(
                not isinstance(file, dict) or set(file) != expected_file_fields
                for file in files
            ):
                fail(f"{transition_path} contains an invalid workspace file")
            paths = [file["path"] for file in files]
            if not all(isinstance(path, str) for path in paths):
                fail(f"{transition_path} contains a non-string workspace path")
            if paths != sorted(paths) or len(paths) != len(set(paths)):
                fail(f"{transition_path} {snapshot_name} paths are not canonical")
            for file in files:
                if not path_validator.is_valid(file["path"]):
                    fail(
                        f"{transition_path} contains a non-canonical workspace path: "
                        f"{file['path']!r}"
                    )
                content_hex = file["contentHex"]
                if (
                    not isinstance(content_hex, str)
                    or len(content_hex) % 2 != 0
                    or any(
                        character not in "0123456789abcdef"
                        for character in content_hex
                    )
                ):
                    fail(f"{transition_path} contains non-canonical contentHex")
                try:
                    content = bytes.fromhex(content_hex)
                except ValueError:
                    fail(f"{transition_path} contains invalid contentHex")
                identity = file["contentIdentity"]
                if not identity_validator.is_valid(identity):
                    fail(f"{transition_path} contains an invalid content identity")
                expected_hash = "sha256:" + hashlib.sha256(content).hexdigest()
                if identity.get("hash") != expected_hash:
                    fail(f"{transition_path} contains an invalid content hash")
                if identity.get("size") != len(content):
                    fail(f"{transition_path} contains an invalid content size")

    title_transition = read_json(
        "golden/workspace-transitions/apply-title-replacement.json"
    )
    dry_run = read_json(APPLY_DRY_RUN_GOLDEN)
    invalid_input = read_json(APPLY_INVALID_INPUT_GOLDEN)
    io_failure = read_json(APPLY_IO_FAILURE_GOLDEN)
    for path, result in [
        (APPLY_DRY_RUN_GOLDEN, dry_run),
        (APPLY_INVALID_INPUT_GOLDEN, invalid_input),
        (APPLY_IO_FAILURE_GOLDEN, io_failure),
    ]:
        errors = sorted(
            validator.iter_errors(result), key=lambda error: list(error.path)
        )
        if errors:
            fail(f"{path} does not match schema: {errors[0].message}")
        require_semantically_valid(result, path)
    require_cli_apply_dry_run(title_transition, dry_run, APPLY_DRY_RUN_GOLDEN)
    require_cli_apply_invalid_input(invalid_input, APPLY_INVALID_INPUT_GOLDEN)
    require_cli_apply_io_failure(
        title_transition, io_failure, APPLY_IO_FAILURE_GOLDEN
    )

    print("golden check passed")


if __name__ == "__main__":
    main()

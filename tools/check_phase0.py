#!/usr/bin/env python3
"""Validate the Phase 0 repository scaffold without external dependencies."""

from __future__ import annotations

import sys
from pathlib import Path

from json_contract import ContractJsonError, loads as strict_json_loads


ROOT = Path(__file__).resolve().parents[1]

REQUIRED_DIRS = [
    "sugar",
    "bitter",
    "schemas",
    "golden",
    "fixtures",
    "docs",
    "protocol",
    "diagnostics",
    "tools",
    "skills",
]

REQUIRED_FILES = [
    "README.md",
    "Makefile",
    ".gitattributes",
    ".editorconfig",
    ".gitignore",
    ".github/workflows/phase0.yml",
    ".github/workflows/release.yml",
    "sugar/dune-project",
    "sugar/monika_sugar.opam",
    "sugar/bin/dune",
    "sugar/bin/main.ml",
    "bitter/Cargo.toml",
    "bitter/src/main.rs",
    "docs/overview.md",
    "docs/architecture.md",
    "docs/implementation-plan.md",
    "docs/logs/bootstrap-log-0001.md",
    "docs/decisions.md",
    "docs/glossary.md",
    "docs/invariants.md",
    "docs/cli-contract.md",
    "docs/scan-filesystem-boundary.md",
    "docs/schema-notes.md",
    "docs/schema-versioning.md",
    "docs/review-2026-07-10.md",
    "docs/pre-alpha-readiness.md",
    "docs/codex-installation.md",
    "docs/codex-reporting.md",
    "docs/codex-update-skill.md",
    "docs/agent-query-api.md",
    "docs/extension-protocol.md",
    "docs/extension-development.md",
    "docs/extension-runtime-design.md",
    "docs/fixtures.md",
    "protocol/extension-protocol.md",
    "diagnostics/codes.md",
    "fixtures/basic/README.md",
    "fixtures/basic/docs/linking.md",
    "fixtures/basic/docs/linking.annotations.yaml",
    "fixtures/basic/src/resolve.ts",
    "fixtures/basic/runs/metrics.jsonl",
    "tools/check_phase0.py",
    "tools/check_golden.py",
    "tools/json_contract.py",
    "tools/test_json_contract.py",
    "tools/semantic_contract.py",
    "tools/test_semantic_contract.py",
    "tools/check_bitter.py",
    "tools/check_distribution.py",
    "tools/release_assets.py",
    "tools/test_release_assets.py",
    "tools/test_report_bundle.py",
    "tools/requirements-ci.txt",
    "skills/monika/SKILL.md",
    "skills/monika/agents/openai.yaml",
    "skills/monika-report/SKILL.md",
    "skills/monika-report/agents/openai.yaml",
    "skills/monika-report/scripts/report_bundle.py",
    "skills/monika-report/scripts/submit_report.py",
    "skills/monika-update/SKILL.md",
    "skills/monika-update/agents/openai.yaml",
    "spec/protocol-integers.json",
    "spec/extension-runtime-initialize-session.json",
    "spec/extension-runtime-methods.json",
    "spec/utf8.json",
    "golden/normal-form/inspect-observations.command-result.json",
    "fixtures/extensions/valid-manifest.json",
    "fixtures/extensions/valid-runtime.py",
    "fixtures/extensions/unsupported-version-manifest.json",
    "fixtures/ignore/keep.generated",
]

SCHEMA_FILES = [
    "schemas/observation.schema.json",
    "schemas/interpretation.schema.json",
    "schemas/region.schema.json",
    "schemas/reference.schema.json",
    "schemas/annotation.schema.json",
    "schemas/diagnostic.schema.json",
    "schemas/patch.schema.json",
    "schemas/capability.schema.json",
    "schemas/snapshot.schema.json",
    "schemas/command-result.schema.json",
    "schemas/extension-manifest.schema.json",
    "schemas/extension-registry.schema.json",
    "schemas/extension-runtime-initialize-session.schema.json",
    "schemas/extension-runtime-methods.schema.json",
    "schemas/related-result.schema.json",
    "schemas/report-bundle-manifest.schema.json",
    "schemas/release-manifest.schema.json",
    "schemas/skill-package-manifest.schema.json",
    "schemas/sidecar-v1.schema.json",
]

GOLDEN_FILES = [
    "golden/cli/capabilities.expected.json",
    "golden/cli/extension-test.expected.json",
    "golden/cli/extension-runtime-test.expected.json",
    "golden/cli/extension-inspect.expected.json",
    "golden/cli/extension-test-unsupported-version.expected.json",
    "golden/cli/apply-dry-run.expected.json",
    "golden/cli/apply-io-failure.expected.json",
    "golden/cli/apply-invalid-input.expected.json",
    "golden/scan/basic.expected.json",
    "golden/inspect/linking.expected.json",
    "golden/resolve/latency-run-a.expected.json",
    "golden/check/basic.expected.json",
    "golden/derive/linking-to-sidecar.expected.json",
    "golden/derive/missing-sidecar.expected.json",
    "golden/related/linking.expected.json",
    "golden/related/linking.expected.txt",
    "golden/read/linking.expected.txt",
]

FIXTURE_CASES = [
    "markdown-inline-link",
    "sidecar-only",
    "inline-only",
    "divergent",
    "stale-selector",
    "unreferenced-ref",
    "unresolved-ref",
    "source-comment-annotation",
    "jsonl-pinned-reference",
]

EXPECTED_CHECK_CODES = [
    "sidecar-only",
    "inline-only",
    "divergent",
    "stale-selector",
    "unreferenced-ref",
    "unresolved-ref",
]

TYPO_CHECKS = {
    "AGENTS.md": [
        "導出する（" + "derive\n",
        "など" + "など",
        "Derive" + "されない",
        "material" + "izer",
    ],
    "PLAN_GLOBAL.md": [
        "正規表現" + "だが",
        "更新した場合" + "Commit",
    ],
}


def fail(message: str) -> None:
    print(f"phase0 check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def read_json(path: str):
    try:
        return strict_json_loads(read_text(path), source=path)
    except ContractJsonError as error:
        fail(str(error))


def require_paths() -> None:
    for path in REQUIRED_DIRS:
        if not (ROOT / path).is_dir():
            fail(f"missing directory: {path}")

    for path in REQUIRED_FILES + SCHEMA_FILES + GOLDEN_FILES:
        if not (ROOT / path).is_file():
            fail(f"missing file: {path}")


def validate_json_files() -> None:
    for path in SCHEMA_FILES:
        data = read_json(path)
        for key in ["$schema", "$id", "title"]:
            if key not in data:
                fail(f"schema {path} is missing {key}")
        if "type" in data and data["type"] != "object":
            fail(f"schema {path} must describe an object")

    scan = read_json("golden/scan/basic.expected.json")
    if scan.get("schemaVersion") != "9":
        fail("golden/scan/basic.expected.json must use command-result schemaVersion 9")
    if scan.get("command") != "scan":
        fail("golden/scan/basic.expected.json must be a scan result")


def validate_fixture_inventory() -> None:
    text = read_text("fixtures/basic/README.md")
    for case in FIXTURE_CASES:
        if case not in text:
            fail(f"fixtures/basic README is missing case: {case}")

    metrics = read_text("fixtures/basic/runs/metrics.jsonl").splitlines()
    for index, line in enumerate(metrics, start=1):
        try:
            strict_json_loads(
                line, source=f"fixtures/basic/runs/metrics.jsonl:{index}"
            )
        except ContractJsonError as exc:
            fail(f"invalid JSONL at fixtures/basic/runs/metrics.jsonl:{index}: {exc}")

    sidecar = read_text("fixtures/basic/docs/linking.annotations.yaml")
    if "path: fixtures/basic/" in sidecar:
        fail("basic sidecar paths must be relative to the fixtures/basic workspace")

    check_result = read_json("golden/check/basic.expected.json")
    actual_codes = [
        diagnostic.get("code") for diagnostic in check_result.get("diagnostics", [])
    ]
    if sorted(actual_codes) != sorted(EXPECTED_CHECK_CODES):
        fail("check golden diagnostic inventory is missing or duplicated")
    registry = read_text("diagnostics/codes.md")
    for code in EXPECTED_CHECK_CODES:
        if f"`{code}`" not in registry:
            fail(f"check golden uses an unknown diagnostic code: {code}")


def validate_typo_fixes() -> None:
    for path, forbidden_tokens in TYPO_CHECKS.items():
        text = read_text(path)
        for token in forbidden_tokens:
            if token in text:
                fail(f"forbidden typo token remains in {path}: {token!r}")


def main() -> None:
    require_paths()
    validate_json_files()
    validate_fixture_inventory()
    validate_typo_fixes()
    print("phase0 check passed")


if __name__ == "__main__":
    main()

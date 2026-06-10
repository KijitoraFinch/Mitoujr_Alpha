#!/usr/bin/env python3
"""Validate the Phase 0 repository scaffold without external dependencies."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


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
]

REQUIRED_FILES = [
    "README.md",
    "Makefile",
    ".editorconfig",
    ".gitignore",
    ".github/workflows/phase0.yml",
    "sugar/dune-project",
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
    "docs/schema-notes.md",
    "docs/extension-protocol.md",
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
]

SCHEMA_FILES = [
    "schemas/artifact.schema.json",
    "schemas/region.schema.json",
    "schemas/reference.schema.json",
    "schemas/annotation.schema.json",
    "schemas/diagnostic.schema.json",
    "schemas/patch.schema.json",
    "schemas/capability.schema.json",
    "schemas/snapshot.schema.json",
]

GOLDEN_FILES = [
    "golden/scan/basic.expected.json",
    "golden/inspect/linking.expected.json",
    "golden/resolve/latency-run-a.expected.json",
    "golden/check/basic.expected.json",
    "golden/derive/linking-to-sidecar.expected.json",
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


def require_paths() -> None:
    for path in REQUIRED_DIRS:
        if not (ROOT / path).is_dir():
            fail(f"missing directory: {path}")

    for path in REQUIRED_FILES + SCHEMA_FILES + GOLDEN_FILES:
        if not (ROOT / path).is_file():
            fail(f"missing file: {path}")


def validate_json_files() -> None:
    for path in SCHEMA_FILES:
        data = json.loads(read_text(path))
        for key in ["$schema", "$id", "title", "type"]:
            if key not in data:
                fail(f"schema {path} is missing {key}")
        if data["type"] != "object":
            fail(f"schema {path} must have object type in Phase 0")

    for path in GOLDEN_FILES:
        data = json.loads(read_text(path))
        if data.get("schemaVersion") != "0.0.0-phase0":
            fail(f"golden {path} must use Phase 0 schemaVersion")
        if data.get("status") != "scaffold-only":
            fail(f"golden {path} must be marked scaffold-only")


def validate_markdown_links(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("#"):
        fail(f"Markdown file must start with a heading: {path.relative_to(ROOT)}")

    for target in re.findall(r"\[[^\]]+\]\(([^)]+)\)", text):
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        target_path = target.split("#", 1)[0]
        if not target_path:
            continue
        resolved = (path.parent / target_path).resolve()
        if not resolved.exists():
            fail(f"broken Markdown link in {path.relative_to(ROOT)}: {target}")

    for target in re.findall(r"\[\[([^\]]+)\]\]", text):
        resolved = (path.parent / target).resolve()
        if not resolved.exists():
            fail(f"broken wiki link in {path.relative_to(ROOT)}: {target}")


def validate_markdown() -> None:
    for path in sorted(ROOT.rglob("*.md")):
        if any(part in {"_build", "target"} for part in path.parts):
            continue
        validate_markdown_links(path)


def validate_fixture_inventory() -> None:
    text = read_text("fixtures/basic/README.md")
    for case in FIXTURE_CASES:
        if case not in text:
            fail(f"fixtures/basic README is missing case: {case}")

    metrics = read_text("fixtures/basic/runs/metrics.jsonl").splitlines()
    for index, line in enumerate(metrics, start=1):
        try:
            json.loads(line)
        except json.JSONDecodeError as exc:
            fail(f"invalid JSONL at fixtures/basic/runs/metrics.jsonl:{index}: {exc}")


def validate_typo_fixes() -> None:
    for path, forbidden_tokens in TYPO_CHECKS.items():
        text = read_text(path)
        for token in forbidden_tokens:
            if token in text:
                fail(f"forbidden typo token remains in {path}: {token!r}")


def main() -> None:
    require_paths()
    validate_json_files()
    validate_markdown()
    validate_fixture_inventory()
    validate_typo_fixes()
    print("phase0 check passed")


if __name__ == "__main__":
    main()

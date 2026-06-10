#!/usr/bin/env python3
"""Validate Phase 0 golden-output scaffolds."""

from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

GOLDEN_FILES = {
    "golden/scan/basic.expected.json": "scan",
    "golden/inspect/linking.expected.json": "inspect",
    "golden/resolve/latency-run-a.expected.json": "resolve",
    "golden/check/basic.expected.json": "check",
    "golden/derive/linking-to-sidecar.expected.json": "derive",
}


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

    print("golden check passed")


if __name__ == "__main__":
    main()

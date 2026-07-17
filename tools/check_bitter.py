#!/usr/bin/env python3
"""Smoke-check the explicitly retained Bitter scaffold."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from json_contract import ContractJsonError, equal_exact, loads


ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "schemaVersion": "0.0.0-phase0",
    "implementation": "bitter",
    "status": "scaffold",
}


def fail(message: str) -> None:
    print(f"bitter check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    process = subprocess.run(
        [
            "cargo",
            "run",
            "--quiet",
            "--locked",
            "--manifest-path",
            "bitter/Cargo.toml",
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        fail(f"cargo run exited with {process.returncode}: {process.stderr.strip()}")
    try:
        output = loads(process.stdout, source="Bitter stdout")
    except ContractJsonError as error:
        fail(str(error))
    if not equal_exact(output, EXPECTED):
        fail("scaffold output differs from its explicit contract")
    if process.stderr:
        fail(f"unexpected stderr: {process.stderr.strip()}")
    print("bitter scaffold check passed")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build, stage, and execute the installable Sugar distribution."""

from __future__ import annotations

import subprocess
import shutil
import sys
import tempfile
from pathlib import Path

from json_contract import ContractJsonError, equal_exact, load, loads


ROOT = Path(__file__).resolve().parents[1]
CAPABILITIES_GOLDEN = ROOT / "golden/cli/capabilities.expected.json"


def fail(message: str) -> None:
    print(f"distribution check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def run_checked(arguments: list[str], *, cwd: Path = ROOT) -> None:
    completed = subprocess.run(
        arguments,
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        fail(
            f"command exited with {completed.returncode}: {arguments!r}\n"
            f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
        )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="monika-distribution-") as directory:
        temporary = Path(directory)
        source = temporary / "source"
        prefix = temporary / "prefix"
        shutil.copytree(
            ROOT / "sugar",
            source,
            ignore=shutil.ignore_patterns("_build", "*.install"),
        )
        run_checked(
            [
                "dune",
                "build",
                "-p",
                "monika_sugar",
                "@install",
                "@runtest",
            ],
            cwd=source,
        )
        generated_manifest = source / "monika_sugar.opam"
        if generated_manifest.read_bytes() != (ROOT / "sugar" / "monika_sugar.opam").read_bytes():
            fail("isolated package build changed the generated opam manifest")
        run_checked(
            [
                "dune",
                "install",
                "--root",
                str(source),
                "--prefix",
                str(prefix),
            ]
        )
        executable = (
            prefix / "bin" / ("monika.exe" if sys.platform == "win32" else "monika")
        )
        required = [
            executable,
            prefix / "lib" / "monika_sugar" / "dune-package",
            prefix / "lib" / "monika_sugar" / "opam",
            prefix / "doc" / "monika_sugar" / "README.md",
        ]
        missing = [
            str(path.relative_to(prefix)) for path in required if not path.is_file()
        ]
        if missing:
            fail(f"staged distribution is missing: {', '.join(missing)}")

        completed = subprocess.run(
            [str(executable), "capabilities"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            fail("installed monika capabilities returned a nonzero exit code")
        if completed.stderr:
            fail(f"installed monika wrote unexpected stderr: {completed.stderr!r}")
        try:
            actual = loads(completed.stdout, source="installed monika stdout")
            expected = load(CAPABILITIES_GOLDEN)
        except ContractJsonError as error:
            fail(str(error))
        if not equal_exact(actual, expected):
            fail("installed monika capabilities differs from the golden output")

    print("distribution check passed")


if __name__ == "__main__":
    main()

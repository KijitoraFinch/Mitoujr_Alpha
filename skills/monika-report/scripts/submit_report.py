#!/usr/bin/env python3
"""Upload a validated Monika report bundle to the fixed private inbox."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.parse
import zipfile
from pathlib import Path


DESTINATION_REPOSITORY = "MitouJr-2026/reports"
DESTINATION_RELEASE_TAG = "report-inbox"


class SubmissionError(Exception):
    pass


def run_checked(arguments: list[str], label: str) -> None:
    try:
        completed = subprocess.run(
            arguments,
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise SubmissionError(f"could not execute {label}: {error}") from error
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        suffix = f": {detail}" if detail else ""
        raise SubmissionError(
            f"{label} exited with status {completed.returncode}{suffix}"
        )


def validate_bundle(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise SubmissionError(f"report bundle does not exist: {path}")
    try:
        with zipfile.ZipFile(path) as archive:
            manifest = json.loads(archive.read("manifest.json"))
    except (OSError, KeyError, zipfile.BadZipFile, json.JSONDecodeError) as error:
        raise SubmissionError(f"invalid report bundle: {error}") from error

    if manifest.get("schemaVersion") != "1":
        raise SubmissionError("report bundle schemaVersion must be 1")
    expected_destination = {
        "repository": DESTINATION_REPOSITORY,
        "releaseTag": DESTINATION_RELEASE_TAG,
    }
    if manifest.get("destination") != expected_destination:
        raise SubmissionError("report bundle has an unexpected destination")
    report_id = manifest.get("reportId")
    if not isinstance(report_id, str) or path.name != f"monika-report-{report_id}.zip":
        raise SubmissionError("report bundle filename does not match its report ID")
    return manifest


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Submit a Monika report bundle to its private GitHub inbox."
    )
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--gh-command", default="gh")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    manifest = validate_bundle(arguments.bundle)
    gh = arguments.gh_command
    run_checked([gh, "auth", "status", "--hostname", "github.com"], "GitHub auth")
    run_checked(
        [
            gh,
            "release",
            "view",
            DESTINATION_RELEASE_TAG,
            "--repo",
            DESTINATION_REPOSITORY,
        ],
        "report inbox lookup",
    )
    run_checked(
        [
            gh,
            "release",
            "upload",
            DESTINATION_RELEASE_TAG,
            str(arguments.bundle),
            "--repo",
            DESTINATION_REPOSITORY,
        ],
        "report upload",
    )
    asset_name = urllib.parse.quote(arguments.bundle.name)
    url = (
        f"https://github.com/{DESTINATION_REPOSITORY}/releases/download/"
        f"{DESTINATION_RELEASE_TAG}/{asset_name}"
    )
    print(
        json.dumps(
            {
                "assetUrl": url,
                "reportId": manifest["reportId"],
                "repository": DESTINATION_REPOSITORY,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SubmissionError as error:
        print(f"monika report submission failed: {error}", file=sys.stderr)
        raise SystemExit(1)


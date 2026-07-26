#!/usr/bin/env python3
"""Upload a validated Monika report bundle to the fixed private inbox."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import urllib.parse
import uuid
import zipfile
from pathlib import Path


DESTINATION_REPOSITORY = "MitouJr-2026/reports"
DESTINATION_RELEASE_TAG = "report-inbox"
CAPTURE_BOUNDARY = "complete-lines-prefix"
BUNDLE_PAYLOAD_ENTRIES = (
    "report.md",
    "codex/doctor.json",
    "codex/session.jsonl",
    "monika/version.txt",
)
BUNDLE_ENTRIES = ("manifest.json", *BUNDLE_PAYLOAD_ENTRIES)
GITHUB_AUTH_SANDBOX_HINT = (
    "If this check ran inside a Codex sandbox, treat an expired or invalid "
    "authentication result as inconclusive. Retry the same submission with "
    "host network and credential access before changing GitHub authentication."
)


class SubmissionError(Exception):
    pass


def run_checked(
    arguments: list[str],
    label: str,
    *,
    failure_hint: str | None = None,
) -> None:
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
        hint = f" {failure_hint}" if failure_hint else ""
        raise SubmissionError(
            f"{label} exited with status {completed.returncode}{suffix}.{hint}"
        )


def validate_bundle(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise SubmissionError(f"report bundle does not exist: {path}")
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)):
                raise SubmissionError("report bundle contains duplicate entries")
            if set(names) != set(BUNDLE_ENTRIES):
                raise SubmissionError(
                    "report bundle does not contain the exact expected entries"
                )
            manifest = json.loads(archive.read("manifest.json"))
            payloads = {
                name: archive.read(name)
                for name in BUNDLE_PAYLOAD_ENTRIES
            }
    except (OSError, KeyError, zipfile.BadZipFile, json.JSONDecodeError) as error:
        raise SubmissionError(f"invalid report bundle: {error}") from error

    if not isinstance(manifest, dict):
        raise SubmissionError("report bundle manifest must be an object")
    if set(manifest) != {
        "schemaVersion",
        "reportId",
        "createdAt",
        "destination",
        "codex",
        "files",
    }:
        raise SubmissionError("report bundle manifest has unexpected fields")
    if manifest.get("schemaVersion") != "1":
        raise SubmissionError("report bundle schemaVersion must be 1")
    expected_destination = {
        "repository": DESTINATION_REPOSITORY,
        "releaseTag": DESTINATION_RELEASE_TAG,
    }
    if manifest.get("destination") != expected_destination:
        raise SubmissionError("report bundle has an unexpected destination")
    report_id = manifest.get("reportId")
    if not isinstance(report_id, str):
        raise SubmissionError("report bundle report ID must be a UUID")
    try:
        uuid.UUID(report_id)
    except ValueError as error:
        raise SubmissionError("report bundle report ID must be a UUID") from error
    if path.name != f"monika-report-{report_id}.zip":
        raise SubmissionError("report bundle filename does not match its report ID")

    codex = manifest.get("codex")
    if not isinstance(codex, dict) or set(codex) != {
        "threadId",
        "sourceBasename",
        "captureBoundary",
    }:
        raise SubmissionError("report bundle has invalid Codex metadata")
    if (
        not isinstance(codex.get("threadId"), str)
        or not codex["threadId"]
        or not isinstance(codex.get("sourceBasename"), str)
        or not codex["sourceBasename"].endswith(".jsonl")
        or "/" in codex["sourceBasename"]
        or "\\" in codex["sourceBasename"]
        or codex.get("captureBoundary") != CAPTURE_BOUNDARY
    ):
        raise SubmissionError("report bundle has invalid Codex metadata")

    files = manifest.get("files")
    if not isinstance(files, dict) or set(files) != set(BUNDLE_PAYLOAD_ENTRIES):
        raise SubmissionError("report bundle manifest has invalid file identities")
    for name, content in payloads.items():
        expected_identity = files.get(name)
        actual_identity = {
            "bytes": len(content),
            "sha256": hashlib.sha256(content).hexdigest(),
        }
        if expected_identity != actual_identity:
            raise SubmissionError(
                f"report bundle digest or byte length does not match for {name}"
            )
    return manifest


def validate_confirmation(
    manifest: dict[str, object],
    *,
    actual_bundle_sha256: str,
    confirmed_report_id: str | None,
    confirmed_bundle_sha256: str | None,
) -> None:
    if confirmed_report_id is None or confirmed_bundle_sha256 is None:
        raise SubmissionError(
            "explicit user confirmation is required before report upload"
        )
    if confirmed_report_id != manifest.get("reportId"):
        raise SubmissionError(
            "confirmed report ID does not match the validated report bundle"
        )
    if confirmed_bundle_sha256 != actual_bundle_sha256:
        raise SubmissionError(
            "confirmed bundle SHA-256 does not match the validated report bundle"
        )


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise SubmissionError(f"could not hash report bundle: {error}") from error
    return digest.hexdigest()


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Submit a Monika report bundle to its private GitHub inbox."
    )
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--confirmed-report-id", required=True)
    parser.add_argument("--confirmed-bundle-sha256", required=True)
    parser.add_argument("--gh-command", default="gh")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    manifest = validate_bundle(arguments.bundle)
    validate_confirmation(
        manifest,
        actual_bundle_sha256=file_sha256(arguments.bundle),
        confirmed_report_id=arguments.confirmed_report_id,
        confirmed_bundle_sha256=arguments.confirmed_bundle_sha256,
    )
    gh = arguments.gh_command
    run_checked(
        [gh, "auth", "status", "--hostname", "github.com"],
        "GitHub auth",
        failure_hint=GITHUB_AUTH_SANDBOX_HINT,
    )
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
    manifest = validate_bundle(arguments.bundle)
    validate_confirmation(
        manifest,
        actual_bundle_sha256=file_sha256(arguments.bundle),
        confirmed_report_id=arguments.confirmed_report_id,
        confirmed_bundle_sha256=arguments.confirmed_bundle_sha256,
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

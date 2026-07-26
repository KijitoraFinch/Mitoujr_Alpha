#!/usr/bin/env python3
"""Collect one raw Codex session and diagnostic metadata into a report bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path


DESTINATION_REPOSITORY = "MitouJr-2026/reports"
DESTINATION_RELEASE_TAG = "report-inbox"
CAPTURE_BOUNDARY = "complete-lines-prefix"


class ReportError(Exception):
    pass


def default_codex_home() -> Path:
    configured = os.environ.get("CODEX_HOME")
    return Path(configured).expanduser() if configured else Path.home() / ".codex"


def find_session(codex_home: Path, thread_id: str) -> Path:
    if not thread_id or any(character in thread_id for character in ("/", "\\")):
        raise ReportError("Codex thread ID is missing or invalid")

    sessions = codex_home / "sessions"
    if not sessions.is_dir():
        raise ReportError(f"Codex sessions directory does not exist: {sessions}")

    suffix = f"-{thread_id}.jsonl"
    matches = sorted(
        path
        for path in sessions.rglob("*.jsonl")
        if path.is_file() and path.name.endswith(suffix)
    )
    if not matches:
        raise ReportError(f"no Codex session matches thread ID {thread_id}")
    if len(matches) > 1:
        names = ", ".join(path.name for path in matches)
        raise ReportError(
            f"multiple Codex sessions match thread ID {thread_id}: {names}"
        )
    return matches[0]


def read_complete_jsonl_prefix(path: Path) -> bytes:
    try:
        with path.open("rb") as source:
            capture_size = os.fstat(source.fileno()).st_size
            captured = source.read(capture_size)
    except OSError as error:
        raise ReportError(f"could not read Codex session: {error}") from error

    final_newline = captured.rfind(b"\n")
    if final_newline < 0:
        raise ReportError("Codex session has no complete JSONL record")
    return captured[: final_newline + 1]


def file_identity(content: bytes) -> dict[str, int | str]:
    return {
        "bytes": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise ReportError(f"could not hash report bundle: {error}") from error
    return digest.hexdigest()


def write_bundle(
    *,
    output: Path,
    report_id: str,
    created_at: str,
    thread_id: str,
    source_basename: str,
    report_markdown: bytes,
    doctor_json: bytes,
    monika_version: bytes,
    session_jsonl: bytes,
) -> None:
    entries = {
        "report.md": report_markdown,
        "codex/doctor.json": doctor_json,
        "codex/session.jsonl": session_jsonl,
        "monika/version.txt": monika_version,
    }
    manifest = {
        "schemaVersion": "1",
        "reportId": report_id,
        "createdAt": created_at,
        "destination": {
            "repository": DESTINATION_REPOSITORY,
            "releaseTag": DESTINATION_RELEASE_TAG,
        },
        "codex": {
            "threadId": thread_id,
            "sourceBasename": source_basename,
            "captureBoundary": CAPTURE_BOUNDARY,
        },
        "files": {
            name: file_identity(content) for name, content in sorted(entries.items())
        },
    }
    manifest_bytes = (
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix=f".{output.name}.",
            suffix=".tmp",
            dir=output.parent,
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
        with zipfile.ZipFile(
            temporary_path,
            mode="w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=9,
        ) as archive:
            archive.writestr("manifest.json", manifest_bytes)
            for name, content in entries.items():
                archive.writestr(name, content)
        os.replace(temporary_path, output)
    except OSError as error:
        raise ReportError(f"could not write report bundle: {error}") from error
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def run_metadata_command(arguments: list[str], label: str) -> bytes:
    try:
        completed = subprocess.run(
            arguments,
            check=False,
            capture_output=True,
        )
    except OSError as error:
        raise ReportError(f"could not execute {label}: {error}") from error
    if completed.returncode != 0:
        stderr = completed.stderr.decode("utf-8", errors="replace").strip()
        detail = f": {stderr}" if stderr else ""
        raise ReportError(
            f"{label} exited with status {completed.returncode}{detail}"
        )
    if not completed.stdout:
        raise ReportError(f"{label} returned empty stdout")
    return completed.stdout


def validated_doctor_json(
    stdout: bytes,
    returncode: int,
    stderr: bytes,
) -> bytes:
    if not stdout:
        detail = stderr.decode("utf-8", errors="replace").strip()
        suffix = f": {detail}" if detail else ""
        raise ReportError(
            f"codex doctor --json exited with status {returncode}{suffix}"
        )
    try:
        parsed = json.loads(stdout)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReportError(f"codex doctor returned invalid JSON: {error}") from error
    if not isinstance(parsed, dict):
        raise ReportError("codex doctor returned a non-object JSON value")
    return stdout


def run_doctor_json(codex_command: str) -> bytes:
    try:
        completed = subprocess.run(
            [codex_command, "doctor", "--json"],
            check=False,
            capture_output=True,
        )
    except OSError as error:
        raise ReportError(f"could not execute codex doctor --json: {error}") from error
    return validated_doctor_json(
        completed.stdout,
        completed.returncode,
        completed.stderr,
    )


def canonical_utc_now() -> str:
    return (
        datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect the current Codex session into a Monika report bundle."
    )
    parser.add_argument("--summary-file", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path.cwd())
    parser.add_argument("--session", type=Path)
    parser.add_argument("--thread-id")
    parser.add_argument("--codex-home", type=Path)
    parser.add_argument("--codex-command", default="codex")
    parser.add_argument("--monika-command", default="monika")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    thread_id = arguments.thread_id or os.environ.get("CODEX_THREAD_ID")
    if not thread_id:
        raise ReportError(
            "CODEX_THREAD_ID is unavailable; provide --thread-id and --session"
        )

    session = arguments.session
    if session is None:
        session = find_session(
            arguments.codex_home or default_codex_home(),
            thread_id,
        )
    elif not session.is_file():
        raise ReportError(f"explicit Codex session does not exist: {session}")

    try:
        report_markdown = arguments.summary_file.read_bytes()
        report_markdown.decode("utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise ReportError(f"could not read UTF-8 report summary: {error}") from error
    if not report_markdown.strip():
        raise ReportError("report summary must not be empty")

    session_jsonl = read_complete_jsonl_prefix(session)
    doctor_json = run_doctor_json(arguments.codex_command)
    monika_version = run_metadata_command(
        [arguments.monika_command, "--version"],
        "monika --version",
    )

    report_id = str(uuid.uuid4())
    output = arguments.output_dir / f"monika-report-{report_id}.zip"
    write_bundle(
        output=output,
        report_id=report_id,
        created_at=canonical_utc_now(),
        thread_id=thread_id,
        source_basename=session.name,
        report_markdown=report_markdown,
        doctor_json=doctor_json,
        monika_version=monika_version,
        session_jsonl=session_jsonl,
    )

    result = {
        "bundle": str(output.resolve()),
        "bundleSha256": file_sha256(output),
        "capturedBytes": len(session_jsonl),
        "destination": {
            "repository": DESTINATION_REPOSITORY,
            "releaseTag": DESTINATION_RELEASE_TAG,
        },
        "reportId": report_id,
        "sessionBasename": session.name,
        "sessionSha256": hashlib.sha256(session_jsonl).hexdigest(),
    }
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ReportError as error:
        print(f"monika report collection failed: {error}", file=sys.stderr)
        raise SystemExit(1)

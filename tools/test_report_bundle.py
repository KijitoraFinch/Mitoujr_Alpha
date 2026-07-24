#!/usr/bin/env python3
"""Meaningful boundary tests for the Codex report collector."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import tempfile
import unittest
import zipfile
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = (
    ROOT / "skills" / "monika-report" / "scripts" / "report_bundle.py"
)
SUBMIT_MODULE_PATH = (
    ROOT / "skills" / "monika-report" / "scripts" / "submit_report.py"
)


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReportBundleBoundaryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.report_bundle = load_module("report_bundle", MODULE_PATH)
        cls.submit_report = load_module("submit_report", SUBMIT_MODULE_PATH)

    def test_thread_id_selects_session_instead_of_newest_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            codex_home = Path(directory)
            sessions = codex_home / "sessions" / "2026" / "07" / "24"
            sessions.mkdir(parents=True)
            selected = sessions / "rollout-2026-07-24T00-00-00-thread-a.jsonl"
            distractor = sessions / "rollout-2026-07-24T00-00-01-thread-b.jsonl"
            selected.write_bytes(b'{"selected":true}\n')
            distractor.write_bytes(b'{"selected":false}\n')
            os.utime(distractor, (selected.stat().st_atime + 60, selected.stat().st_mtime + 60))

            actual = self.report_bundle.find_session(codex_home, "thread-a")

            self.assertEqual(actual, selected)

    def test_snapshot_preserves_complete_lines_and_excludes_partial_tail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            session = Path(directory) / "session.jsonl"
            complete = '{"message":"日本語"}\n{"value":2}\n'.encode()
            session.write_bytes(complete + b'{"incomplete":')

            actual = self.report_bundle.read_complete_jsonl_prefix(session)

            self.assertEqual(actual, complete)

    def test_manifest_digest_identifies_unchanged_raw_session_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            session_bytes = b'{"type":"session_meta"}\n{"type":"event_msg"}\n'
            report_id = "00000000-0000-4000-8000-000000000001"
            output = root / f"monika-report-{report_id}.zip"
            self.report_bundle.write_bundle(
                output=output,
                report_id=report_id,
                created_at="2026-07-24T00:00:00Z",
                thread_id="thread-a",
                source_basename="rollout-thread-a.jsonl",
                report_markdown=b"# Report\n\nSomething failed.\n",
                doctor_json=b'{"codexVersion":"0.145.0"}\n',
                monika_version=b"monika 27f64a9\n",
                session_jsonl=session_bytes,
            )

            with zipfile.ZipFile(output) as archive:
                captured = archive.read("codex/session.jsonl")
                manifest = json.loads(archive.read("manifest.json"))
            manifest_schema = json.loads(
                (
                    ROOT / "schemas" / "report-bundle-manifest.schema.json"
                ).read_text(encoding="utf-8")
            )

            self.assertEqual(captured, session_bytes)
            Draft202012Validator(
                manifest_schema,
                format_checker=Draft202012Validator.FORMAT_CHECKER,
            ).validate(manifest)
            validated = self.submit_report.validate_bundle(output)
            self.assertEqual(validated["reportId"], manifest["reportId"])
            self.assertEqual(
                manifest["files"]["codex/session.jsonl"],
                {
                    "bytes": len(session_bytes),
                    "sha256": hashlib.sha256(session_bytes).hexdigest(),
                },
            )

    def test_failed_doctor_status_keeps_valid_redacted_report(self) -> None:
        doctor = b'{"overallStatus":"fail","codexVersion":"0.145.0"}\n'

        actual = self.report_bundle.validated_doctor_json(
            doctor,
            returncode=1,
            stderr=b"diagnostic checks failed",
        )

        self.assertEqual(actual, doctor)


if __name__ == "__main__":
    unittest.main()

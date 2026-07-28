#!/usr/bin/env python3
"""Boundary tests for deterministic Monika release assets."""

from __future__ import annotations

import importlib.util
import json
import stat
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "release_assets.py"
VERSION = "1.2.3-rc.1"
TAG = f"v{VERSION}"
COMMIT = "0123456789abcdef0123456789abcdef01234567"


def load_module():
    spec = importlib.util.spec_from_file_location("release_assets", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ReleaseAssetBoundaryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.release_assets = load_module()

    def test_version_and_identity_are_strict(self) -> None:
        self.assertEqual(
            self.release_assets.build_identity(VERSION, COMMIT),
            "1.2.3-rc.1+0123456789ab",
        )
        for invalid in (
            "1.2",
            "01.2.3",
            "1.2.3-01",
            "1.2.3+local",
            "../1.2.3",
            "1.2.3 rc",
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaises(self.release_assets.ReleaseAssetError):
                    self.release_assets.require_version(invalid)

    def test_observed_host_target_is_supported(self) -> None:
        self.assertIn(
            self.release_assets.observed_host_target(),
            self.release_assets.TARGETS,
        )

    def test_release_metadata_resolves_one_tagged_commit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(
                ["git", "init", "--quiet"],
                cwd=repository,
                check=True,
            )
            (repository / "tracked.txt").write_text(
                "release\n", encoding="utf-8"
            )
            subprocess.run(
                ["git", "add", "tracked.txt"],
                cwd=repository,
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    "-c",
                    "user.name=Monika Test",
                    "-c",
                    "user.email=monika-test@example.invalid",
                    "commit",
                    "--quiet",
                    "-m",
                    "test release",
                ],
                cwd=repository,
                check=True,
            )
            subprocess.run(
                ["git", "tag", TAG],
                cwd=repository,
                check=True,
            )
            metadata = self.release_assets.resolve_metadata(
                repository=repository,
                tag=TAG,
            )
            self.assertEqual(metadata["version"], VERSION)
            self.assertRegex(metadata["commit"], r"^[0-9a-f]{40}$")
            self.assertEqual(
                metadata["identity"],
                f"{VERSION}+{metadata['commit'][:12]}",
            )

    def test_skill_archive_is_deterministic_and_closed(self) -> None:
        with tempfile.TemporaryDirectory() as first_directory:
            with tempfile.TemporaryDirectory() as second_directory:
                first = self.release_assets.package_skills(
                    output_dir=Path(first_directory),
                    version=VERSION,
                    commit=COMMIT,
                )
                second = self.release_assets.package_skills(
                    output_dir=Path(second_directory),
                    version=VERSION,
                    commit=COMMIT,
                )
                self.assertEqual(first.read_bytes(), second.read_bytes())

                root_name = f"monika-skills-{VERSION}"
                with zipfile.ZipFile(first) as archive:
                    self.assertEqual(
                        set(archive.namelist()),
                        {
                            f"{root_name}/manifest.json",
                            *(
                                f"{root_name}/skills/{relative}"
                                for relative in self.release_assets.SKILL_FILES
                            ),
                        },
                    )
                    manifest = json.loads(
                        archive.read(f"{root_name}/manifest.json")
                    )
                    self.assertEqual(
                        [entry["path"] for entry in manifest["files"]],
                        list(self.release_assets.SKILL_FILES),
                    )

    def test_skill_archive_rejects_modified_content(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = self.release_assets.package_skills(
                output_dir=root,
                version=VERSION,
                commit=COMMIT,
            )
            modified = root / "modified.zip"
            with zipfile.ZipFile(original) as source:
                entries = [
                    (info, source.read(info.filename))
                    for info in source.infolist()
                ]
            skill_entry = next(
                info.filename
                for info, _ in entries
                if info.filename.endswith("/monika/SKILL.md")
            )
            with zipfile.ZipFile(modified, "w") as destination:
                for info, content in entries:
                    if info.filename == skill_entry:
                        content += b"\nmodified\n"
                    destination.writestr(info, content)
            with self.assertRaisesRegex(
                self.release_assets.ReleaseAssetError,
                "content identity differs",
            ):
                self.release_assets.verify_skill_archive(
                    modified, version=VERSION, commit=COMMIT
                )

    def test_skill_archive_rejects_symbolic_link_entry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = self.release_assets.package_skills(
                output_dir=root,
                version=VERSION,
                commit=COMMIT,
            )
            modified = root / "symlink.zip"
            with zipfile.ZipFile(original) as source:
                entries = [
                    (info, source.read(info.filename))
                    for info in source.infolist()
                ]
            skill_entry = next(
                info.filename
                for info, _ in entries
                if info.filename.endswith("/monika/SKILL.md")
            )
            with zipfile.ZipFile(modified, "w") as destination:
                for info, content in entries:
                    if info.filename == skill_entry:
                        info.external_attr = (stat.S_IFLNK | 0o777) << 16
                        content = b"../outside"
                    destination.writestr(info, content)
            with self.assertRaisesRegex(
                self.release_assets.ReleaseAssetError,
                "not a regular file",
            ):
                self.release_assets.verify_skill_archive(
                    modified, version=VERSION, commit=COMMIT
                )

    def test_finalize_and_verify_reject_tampering(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            assets = Path(directory)
            for target in self.release_assets.TARGETS:
                path = assets / self.release_assets.cli_asset_name(VERSION, target)
                path.write_bytes(f"binary:{target}".encode())
            self.release_assets.package_skills(
                output_dir=assets,
                version=VERSION,
                commit=COMMIT,
            )
            self.release_assets.finalize_release(
                assets_dir=assets,
                version=VERSION,
                tag=TAG,
                commit=COMMIT,
            )
            self.release_assets.verify_release(
                assets_dir=assets,
                version=VERSION,
                tag=TAG,
                commit=COMMIT,
            )
            release_manifest = json.loads(
                (assets / "release-manifest.json").read_text(encoding="utf-8")
            )
            release_schema = json.loads(
                (ROOT / "schemas/release-manifest.schema.json").read_text(
                    encoding="utf-8"
                )
            )
            Draft202012Validator(release_schema).validate(release_manifest)

            skills_path = assets / self.release_assets.skill_asset_name(VERSION)
            root_name = f"monika-skills-{VERSION}"
            with zipfile.ZipFile(skills_path) as archive:
                skill_manifest = json.loads(
                    archive.read(f"{root_name}/manifest.json")
                )
            skill_schema = json.loads(
                (ROOT / "schemas/skill-package-manifest.schema.json").read_text(
                    encoding="utf-8"
                )
            )
            Draft202012Validator(skill_schema).validate(skill_manifest)

            tampered = assets / self.release_assets.cli_asset_name(
                VERSION, "linux-x86_64"
            )
            tampered.write_bytes(b"tampered")
            with self.assertRaisesRegex(
                self.release_assets.ReleaseAssetError,
                "content identity differs",
            ):
                self.release_assets.verify_release(
                    assets_dir=assets,
                    version=VERSION,
                    tag=TAG,
                    commit=COMMIT,
                )


if __name__ == "__main__":
    unittest.main()

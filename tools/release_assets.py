#!/usr/bin/env python3
"""Build and verify Monika binary-release assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import re
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Any

from json_contract import (
    ContractJsonError,
    load as load_strict_json,
    loads as loads_strict_json,
)


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_VERSION = "1"
PRERELEASE_IDENTIFIER = (
    r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
)
VERSION_PATTERN = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
    rf"(?:-{PRERELEASE_IDENTIFIER}(?:\.{PRERELEASE_IDENTIFIER})*)?"
)
COMMIT_PATTERN = re.compile(r"[0-9a-f]{40}")
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
TARGETS = {
    "linux-x86_64": ("linux", "x86_64", ""),
    "macos-aarch64": ("macos", "aarch64", ""),
    "macos-x86_64": ("macos", "x86_64", ""),
    "windows-x86_64": ("windows", "x86_64", ".exe"),
}
SKILL_FILES = (
    "monika/SKILL.md",
    "monika/agents/openai.yaml",
    "monika-report/SKILL.md",
    "monika-report/agents/openai.yaml",
    "monika-report/scripts/report_bundle.py",
    "monika-report/scripts/submit_report.py",
    "monika-update/SKILL.md",
    "monika-update/agents/openai.yaml",
)


class ReleaseAssetError(ValueError):
    """Raised when a release asset violates the distribution contract."""


def fail(message: str) -> None:
    print(f"release asset error: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_version(value: str) -> str:
    if VERSION_PATTERN.fullmatch(value) is None:
        raise ReleaseAssetError(
            "version must be SemVer without build metadata, for example 1.2.3 "
            "or 1.2.3-rc.1"
        )
    return value


def require_tag(value: str) -> tuple[str, str]:
    if not value.startswith("v"):
        raise ReleaseAssetError("release tag must have the form v<version>")
    version = require_version(value[1:])
    return value, version


def require_commit(value: str) -> str:
    normalized = value.lower()
    if COMMIT_PATTERN.fullmatch(normalized) is None:
        raise ReleaseAssetError("commit must be one full 40-character Git object ID")
    return normalized


def require_target(value: str) -> str:
    if value not in TARGETS:
        raise ReleaseAssetError(
            f"unsupported target {value!r}; expected one of {sorted(TARGETS)}"
        )
    return value


def observed_host_target() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()
    normalized_machine = {
        "amd64": "x86_64",
        "arm64": "aarch64",
    }.get(machine, machine)
    platform_name = {
        "darwin": "macos",
        "linux": "linux",
        "windows": "windows",
    }.get(system)
    target = (
        f"{platform_name}-{normalized_machine}"
        if platform_name is not None
        else ""
    )
    if target not in TARGETS:
        raise ReleaseAssetError(
            f"unsupported build host: system={system!r}, machine={machine!r}"
        )
    return target


def build_identity(version: str, commit: str) -> str:
    return f"{require_version(version)}+{require_commit(commit)[:12]}"


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")


def cli_asset_name(version: str, target: str) -> str:
    _, _, extension = TARGETS[require_target(target)]
    return f"monika-{require_version(version)}-{target}{extension}"


def skill_asset_name(version: str) -> str:
    return f"monika-skills-{require_version(version)}.zip"


def run_cli_smoke(executable: Path, identity: str) -> None:
    if not executable.is_file() or executable.is_symlink():
        raise ReleaseAssetError(f"CLI is not a regular file: {executable}")

    try:
        version = subprocess.run(
            [str(executable), "--version"],
            check=False,
            capture_output=True,
            text=True,
        )
        capabilities = subprocess.run(
            [str(executable), "capabilities"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise ReleaseAssetError(f"cannot execute CLI: {error}") from error

    expected_version = f"monika {identity}\n"
    if (
        version.returncode != 0
        or version.stdout != expected_version
        or version.stderr
    ):
        raise ReleaseAssetError(
            "CLI version smoke test failed: "
            f"exit={version.returncode}, stdout={version.stdout!r}, "
            f"stderr={version.stderr!r}, expected={expected_version!r}"
        )
    if capabilities.returncode != 0 or capabilities.stderr:
        raise ReleaseAssetError(
            "CLI capabilities smoke test failed: "
            f"exit={capabilities.returncode}, stderr={capabilities.stderr!r}"
        )
    try:
        result = loads_strict_json(
            capabilities.stdout, source="monika capabilities stdout"
        )
    except ContractJsonError as error:
        raise ReleaseAssetError(
            f"CLI capabilities returned invalid JSON: {error}"
        ) from error
    if (
        not isinstance(result, dict)
        or result.get("status") != "ok"
        or not result.get("capabilities")
    ):
        raise ReleaseAssetError("CLI capabilities smoke test returned no capabilities")


def package_cli(
    *,
    executable: Path,
    output_dir: Path,
    version: str,
    commit: str,
    target: str,
) -> Path:
    version = require_version(version)
    commit = require_commit(commit)
    target = require_target(target)
    observed_target = observed_host_target()
    if target != observed_target:
        raise ReleaseAssetError(
            f"declared target {target!r} differs from build host {observed_target!r}"
        )
    identity = build_identity(version, commit)
    run_cli_smoke(executable, identity)

    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / cli_asset_name(version, target)
    if output.exists():
        raise ReleaseAssetError(f"refusing to replace existing asset: {output}")
    shutil.copyfile(executable, output)
    if TARGETS[target][0] != "windows":
        output.chmod(0o755)
    return output


def skill_file_identities() -> list[dict[str, Any]]:
    identities = []
    for relative in SKILL_FILES:
        path = ROOT / "skills" / relative
        if not path.is_file() or path.is_symlink():
            raise ReleaseAssetError(
                f"required Skill file is missing: skills/{relative}"
            )
        content = path.read_bytes()
        identities.append(
            {
                "bytes": len(content),
                "path": relative,
                "sha256": sha256_bytes(content),
            }
        )
    return identities


def zip_info(name: str, *, executable: bool = False) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3
    mode = 0o755 if executable else 0o644
    info.external_attr = (stat.S_IFREG | mode) << 16
    return info


def package_skills(
    *, output_dir: Path, version: str, commit: str
) -> Path:
    version = require_version(version)
    commit = require_commit(commit)
    root_name = f"monika-skills-{version}"
    identities = skill_file_identities()
    manifest = {
        "commit": commit,
        "files": identities,
        "schemaVersion": SCHEMA_VERSION,
        "version": version,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / skill_asset_name(version)
    if output.exists():
        raise ReleaseAssetError(f"refusing to replace existing asset: {output}")
    with zipfile.ZipFile(
        output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        archive.writestr(
            zip_info(f"{root_name}/manifest.json"),
            canonical_json_bytes(manifest),
        )
        for identity in identities:
            relative = identity["path"]
            source = ROOT / "skills" / relative
            executable = relative.endswith(".py")
            archive.writestr(
                zip_info(
                    f"{root_name}/skills/{relative}",
                    executable=executable,
                ),
                source.read_bytes(),
            )
    verify_skill_archive(output, version=version, commit=commit)
    return output


def require_exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        raise ReleaseAssetError(
            f"{label} fields differ: expected {sorted(expected)}, got {sorted(actual)}"
        )


def validate_file_identity(value: Any, *, label: str) -> tuple[str, int, str]:
    if not isinstance(value, dict):
        raise ReleaseAssetError(f"{label} must be an object")
    require_exact_keys(value, {"bytes", "path", "sha256"}, label)
    path = value["path"]
    byte_count = value["bytes"]
    digest = value["sha256"]
    if not isinstance(path, str) or not path:
        raise ReleaseAssetError(f"{label}.path must be a non-empty string")
    if (
        not isinstance(byte_count, int)
        or isinstance(byte_count, bool)
        or byte_count < 0
    ):
        raise ReleaseAssetError(f"{label}.bytes must be a nonnegative integer")
    if not isinstance(digest, str) or SHA256_PATTERN.fullmatch(digest) is None:
        raise ReleaseAssetError(f"{label}.sha256 must be a lowercase SHA-256")
    return path, byte_count, digest


def verify_skill_archive(path: Path, *, version: str, commit: str) -> None:
    version = require_version(version)
    commit = require_commit(commit)
    if not path.is_file() or path.is_symlink():
        raise ReleaseAssetError(f"Skill archive is not a regular file: {path}")
    root_name = f"monika-skills-{version}"
    manifest_name = f"{root_name}/manifest.json"
    expected_names = {
        manifest_name,
        *(f"{root_name}/skills/{relative}" for relative in SKILL_FILES),
    }

    try:
        with zipfile.ZipFile(path, "r") as archive:
            entries = archive.infolist()
            names = [entry.filename for entry in entries]
            if len(names) != len(set(names)):
                raise ReleaseAssetError("Skill archive contains duplicate entries")
            if set(names) != expected_names:
                raise ReleaseAssetError(
                    "Skill archive entry set differs from the closed inventory"
                )
            for entry in entries:
                mode = entry.external_attr >> 16
                if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
                    raise ReleaseAssetError(
                        f"Skill archive entry is not a regular file: {entry.filename}"
                    )
            try:
                manifest = loads_strict_json(
                    archive.read(manifest_name).decode("utf-8"),
                    source=manifest_name,
                )
            except (KeyError, UnicodeError, ContractJsonError) as error:
                raise ReleaseAssetError(
                    f"Skill archive manifest is invalid: {error}"
                ) from error
            if not isinstance(manifest, dict):
                raise ReleaseAssetError("Skill archive manifest must be an object")
            require_exact_keys(
                manifest,
                {"commit", "files", "schemaVersion", "version"},
                "Skill archive manifest",
            )
            if manifest["schemaVersion"] != SCHEMA_VERSION:
                raise ReleaseAssetError("unsupported Skill archive schemaVersion")
            if manifest["version"] != version or manifest["commit"] != commit:
                raise ReleaseAssetError(
                    "Skill archive identity differs from the requested release"
                )
            files = manifest["files"]
            if not isinstance(files, list):
                raise ReleaseAssetError("Skill archive manifest files must be an array")
            actual_paths: list[str] = []
            for index, identity in enumerate(files):
                relative, byte_count, digest = validate_file_identity(
                    identity, label=f"Skill archive manifest files[{index}]"
                )
                actual_paths.append(relative)
                content = archive.read(f"{root_name}/skills/{relative}")
                if len(content) != byte_count or sha256_bytes(content) != digest:
                    raise ReleaseAssetError(
                        f"Skill archive content identity differs: {relative}"
                    )
            if actual_paths != list(SKILL_FILES):
                raise ReleaseAssetError(
                    "Skill archive manifest file order or inventory differs"
                )
    except (OSError, zipfile.BadZipFile) as error:
        raise ReleaseAssetError(f"cannot read Skill archive: {error}") from error


def cli_asset_manifest(path: Path, *, version: str, target: str) -> dict[str, Any]:
    platform_name, architecture, _ = TARGETS[target]
    return {
        "architecture": architecture,
        "bytes": path.stat().st_size,
        "kind": "cli",
        "name": path.name,
        "platform": platform_name,
        "sha256": sha256_file(path),
    }


def skills_asset_manifest(path: Path) -> dict[str, Any]:
    return {
        "bytes": path.stat().st_size,
        "kind": "skills",
        "name": path.name,
        "sha256": sha256_file(path),
    }


def finalize_release(
    *,
    assets_dir: Path,
    version: str,
    tag: str,
    commit: str,
) -> tuple[Path, Path]:
    version = require_version(version)
    required_tag, tag_version = require_tag(tag)
    commit = require_commit(commit)
    if tag_version != version:
        raise ReleaseAssetError("tag and release version differ")
    if not assets_dir.is_dir():
        raise ReleaseAssetError(f"asset directory does not exist: {assets_dir}")

    expected_initial = {
        *(cli_asset_name(version, target) for target in TARGETS),
        skill_asset_name(version),
    }
    actual_initial = {entry.name for entry in assets_dir.iterdir()}
    if actual_initial != expected_initial:
        raise ReleaseAssetError(
            "release asset set differs before finalization: "
            f"expected {sorted(expected_initial)}, got {sorted(actual_initial)}"
        )

    assets: list[dict[str, Any]] = []
    for target in TARGETS:
        path = assets_dir / cli_asset_name(version, target)
        if not path.is_file() or path.is_symlink():
            raise ReleaseAssetError(f"CLI asset is not a regular file: {path}")
        assets.append(cli_asset_manifest(path, version=version, target=target))
    skills_path = assets_dir / skill_asset_name(version)
    verify_skill_archive(skills_path, version=version, commit=commit)
    assets.append(skills_asset_manifest(skills_path))
    assets.sort(key=lambda asset: asset["name"])

    manifest = {
        "assets": assets,
        "commit": commit,
        "schemaVersion": SCHEMA_VERSION,
        "tag": required_tag,
        "version": version,
    }
    manifest_path = assets_dir / "release-manifest.json"
    sums_path = assets_dir / "SHA256SUMS"
    if manifest_path.exists() or sums_path.exists():
        raise ReleaseAssetError("refusing to replace finalized release metadata")
    manifest_path.write_bytes(canonical_json_bytes(manifest))

    checksummed = [*(assets_dir / asset["name"] for asset in assets), manifest_path]
    with sums_path.open("x", encoding="utf-8", newline="\n") as output:
        output.write(
            "".join(
                f"{sha256_file(path)}  {path.name}\n" for path in checksummed
            )
        )
    verify_release(
        assets_dir=assets_dir, version=version, tag=tag, commit=commit
    )
    return manifest_path, sums_path


def verify_release(
    *,
    assets_dir: Path,
    version: str,
    tag: str,
    commit: str,
) -> None:
    version = require_version(version)
    required_tag, tag_version = require_tag(tag)
    commit = require_commit(commit)
    if version != tag_version:
        raise ReleaseAssetError("tag and release version differ")
    expected_names = {
        *(cli_asset_name(version, target) for target in TARGETS),
        skill_asset_name(version),
        "release-manifest.json",
        "SHA256SUMS",
    }
    actual_names = {entry.name for entry in assets_dir.iterdir()}
    if actual_names != expected_names:
        raise ReleaseAssetError(
            "final release entry set differs: "
            f"expected {sorted(expected_names)}, got {sorted(actual_names)}"
        )
    for name in expected_names:
        path = assets_dir / name
        if not path.is_file() or path.is_symlink():
            raise ReleaseAssetError(
                f"final release entry is not a regular file: {name}"
            )

    try:
        manifest = load_strict_json(assets_dir / "release-manifest.json")
    except ContractJsonError as error:
        raise ReleaseAssetError(str(error)) from error
    if not isinstance(manifest, dict):
        raise ReleaseAssetError("release manifest must be an object")
    require_exact_keys(
        manifest,
        {"assets", "commit", "schemaVersion", "tag", "version"},
        "release manifest",
    )
    if (
        manifest["schemaVersion"] != SCHEMA_VERSION
        or manifest["version"] != version
        or manifest["tag"] != required_tag
        or manifest["commit"] != commit
    ):
        raise ReleaseAssetError("release manifest identity differs")
    assets = manifest["assets"]
    if not isinstance(assets, list):
        raise ReleaseAssetError("release manifest assets must be an array")

    expected_asset_names = sorted(
        expected_names - {"release-manifest.json", "SHA256SUMS"}
    )
    actual_asset_names: list[str] = []
    expected_cli_metadata = {
        cli_asset_name(version, target): TARGETS[target][:2]
        for target in TARGETS
    }
    for index, asset in enumerate(assets):
        if not isinstance(asset, dict):
            raise ReleaseAssetError(f"release asset {index} must be an object")
        kind = asset.get("kind")
        if kind not in {"cli", "skills"}:
            raise ReleaseAssetError(f"release asset {index} has an invalid kind")
        common = {"bytes", "kind", "name", "sha256"}
        expected_fields = (
            common | {"architecture", "platform"} if kind == "cli" else common
        )
        require_exact_keys(asset, expected_fields, f"release asset {index}")
        name = asset["name"]
        byte_count = asset["bytes"]
        digest = asset["sha256"]
        if not isinstance(name, str) or name not in expected_asset_names:
            raise ReleaseAssetError(f"release asset {index} has an invalid name")
        if kind == "cli":
            expected_platform, expected_architecture = expected_cli_metadata.get(
                name, (None, None)
            )
            if (
                asset["platform"] != expected_platform
                or asset["architecture"] != expected_architecture
            ):
                raise ReleaseAssetError(
                    f"release asset target metadata differs: {name}"
                )
        elif name != skill_asset_name(version):
            raise ReleaseAssetError(
                f"release Skill asset has an invalid name: {name}"
            )
        if (
            not isinstance(byte_count, int)
            or isinstance(byte_count, bool)
            or byte_count < 0
        ):
            raise ReleaseAssetError(f"release asset {index} has invalid bytes")
        if not isinstance(digest, str) or SHA256_PATTERN.fullmatch(digest) is None:
            raise ReleaseAssetError(f"release asset {index} has invalid SHA-256")
        path = assets_dir / name
        if path.stat().st_size != byte_count or sha256_file(path) != digest:
            raise ReleaseAssetError(f"release asset content identity differs: {name}")
        actual_asset_names.append(name)
    if actual_asset_names != expected_asset_names:
        raise ReleaseAssetError("release manifest asset order or inventory differs")

    sums_path = assets_dir / "SHA256SUMS"
    try:
        lines = sums_path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise ReleaseAssetError(f"cannot read SHA256SUMS: {error}") from error
    expected_summed_names = [
        *expected_asset_names,
        "release-manifest.json",
    ]
    if len(lines) != len(expected_summed_names):
        raise ReleaseAssetError("SHA256SUMS entry count differs")
    for line, expected_name in zip(lines, expected_summed_names):
        expected_line = f"{sha256_file(assets_dir / expected_name)}  {expected_name}"
        if line != expected_line:
            raise ReleaseAssetError(
                f"SHA256SUMS entry differs for {expected_name}"
            )
    verify_skill_archive(
        assets_dir / skill_asset_name(version),
        version=version,
        commit=commit,
    )


def resolve_metadata(*, repository: Path, tag: str) -> dict[str, str]:
    tag, version = require_tag(tag)
    try:
        commit_result = subprocess.run(
            ["git", "rev-parse", f"{tag}^{{commit}}"],
            cwd=repository,
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise ReleaseAssetError(f"cannot execute git: {error}") from error
    if commit_result.returncode != 0 or commit_result.stderr:
        raise ReleaseAssetError(
            f"cannot resolve release tag {tag!r}: {commit_result.stderr.strip()}"
        )
    commit = require_commit(commit_result.stdout.strip())
    return {
        "commit": commit,
        "identity": build_identity(version, commit),
        "tag": tag,
        "version": version,
    }


def write_github_outputs(path: Path, metadata: dict[str, str]) -> None:
    with path.open("a", encoding="utf-8", newline="\n") as output:
        for name in ("commit", "identity", "tag", "version"):
            output.write(f"{name}={metadata[name]}\n")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)

    metadata = commands.add_parser("metadata")
    metadata.add_argument("--repository", type=Path, default=ROOT)
    metadata.add_argument("--tag", required=True)
    metadata.add_argument("--github-output", type=Path)

    cli = commands.add_parser("package-cli")
    cli.add_argument("--executable", type=Path, required=True)
    cli.add_argument("--output-dir", type=Path, required=True)
    cli.add_argument("--version", required=True)
    cli.add_argument("--commit", required=True)
    cli.add_argument("--target", required=True)

    skills = commands.add_parser("package-skills")
    skills.add_argument("--output-dir", type=Path, required=True)
    skills.add_argument("--version", required=True)
    skills.add_argument("--commit", required=True)

    finalize = commands.add_parser("finalize")
    finalize.add_argument("--assets-dir", type=Path, required=True)
    finalize.add_argument("--version", required=True)
    finalize.add_argument("--tag", required=True)
    finalize.add_argument("--commit", required=True)

    verify = commands.add_parser("verify")
    verify.add_argument("--assets-dir", type=Path, required=True)
    verify.add_argument("--version", required=True)
    verify.add_argument("--tag", required=True)
    verify.add_argument("--commit", required=True)
    return result


def main() -> None:
    arguments = parser().parse_args()
    try:
        if arguments.command == "metadata":
            metadata = resolve_metadata(
                repository=arguments.repository, tag=arguments.tag
            )
            if arguments.github_output is not None:
                write_github_outputs(arguments.github_output, metadata)
            print(json.dumps(metadata, sort_keys=True))
        elif arguments.command == "package-cli":
            output = package_cli(
                executable=arguments.executable,
                output_dir=arguments.output_dir,
                version=arguments.version,
                commit=arguments.commit,
                target=arguments.target,
            )
            print(output)
        elif arguments.command == "package-skills":
            output = package_skills(
                output_dir=arguments.output_dir,
                version=arguments.version,
                commit=arguments.commit,
            )
            print(output)
        elif arguments.command == "finalize":
            manifest, sums = finalize_release(
                assets_dir=arguments.assets_dir,
                version=arguments.version,
                tag=arguments.tag,
                commit=arguments.commit,
            )
            print(manifest)
            print(sums)
        elif arguments.command == "verify":
            verify_release(
                assets_dir=arguments.assets_dir,
                version=arguments.version,
                tag=arguments.tag,
                commit=arguments.commit,
            )
            print("release assets verified")
        else:
            raise AssertionError(f"unhandled command: {arguments.command}")
    except (OSError, ReleaseAssetError) as error:
        fail(str(error))


if __name__ == "__main__":
    main()

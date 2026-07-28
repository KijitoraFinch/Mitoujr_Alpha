#!/usr/bin/env python3
"""Validate semantic constraints not expressible in JSON Schema."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

from json_contract import ContractJsonError, load as strict_json_load


APPLY_INTERNAL_ERROR_CODES = {
    "filesystem-io",
    "internal-invariant",
    "resource-exhausted",
}
APPLY_INTERNAL_OPERATIONS = {
    "acquire-target-lock",
    "allocate-temporary-name",
    "atomic-replace",
    "construct-workspace-snapshot",
    "create-temporary",
    "enumerate-parent",
    "flush-parent",
    "flush-temporary",
    "flush-temporary-metadata",
    "inspect-path-component",
    "inspect-target",
    "open-parent",
    "open-target",
    "open-workspace",
    "prepare-temporary",
    "read-applied-workspace-snapshot",
    "read-target",
    "set-temporary-metadata",
    "write-temporary",
}


def walk_json(value, path: str = "$"):
    yield path, value
    if isinstance(value, dict):
        for key, child in value.items():
            yield from walk_json(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk_json(child, f"{path}[{index}]")


def patch_ranges(patch, path: str):
    for index, edit in enumerate(patch.get("edits", [])):
        yield f"{path}.edits[{index}].range", edit.get("range")


def command_result_ranges(result):
    for index, patch in enumerate(result.get("patches", [])):
        yield from patch_ranges(patch, f"$.patches[{index}]")
    for diagnostic_index, diagnostic in enumerate(result.get("diagnostics", [])):
        location = diagnostic.get("location")
        if isinstance(location, dict) and "range" in location:
            yield (
                f"$.diagnostics[{diagnostic_index}].location.range",
                location["range"],
            )
        for patch_index, patch in enumerate(diagnostic.get("suggestedFixes", [])):
            yield from patch_ranges(
                patch,
                f"$.diagnostics[{diagnostic_index}].suggestedFixes[{patch_index}]",
            )
    for index, conflict in enumerate(result.get("conflicts", [])):
        for field in ["range", "left", "right"]:
            if field in conflict:
                yield f"$.conflicts[{index}].{field}", conflict[field]
    for index, snapshot in enumerate(result.get("snapshots", [])):
        selector = snapshot.get("target", {}).get("selector")
        if isinstance(selector, dict) and selector.get("kind") == "text-range":
            yield f"$.snapshots[{index}].target.selector.range", selector.get("range")

def command_result_patches(result):
    for index, patch in enumerate(result.get("patches", [])):
        yield f"$.patches[{index}]", patch
    for diagnostic_index, diagnostic in enumerate(result.get("diagnostics", [])):
        for patch_index, patch in enumerate(diagnostic.get("suggestedFixes", [])):
            yield (
                f"$.diagnostics[{diagnostic_index}].suggestedFixes[{patch_index}]",
                patch,
            )


def identity_key(value):
    if not isinstance(value, dict):
        return None
    return value.get("hash"), value.get("size")


def conflict_errors(conflict, path: str) -> list[str]:
    if not isinstance(conflict, dict):
        return []
    kind = conflict.get("kind")
    if kind == "identity-mismatch":
        if identity_key(conflict.get("expected")) == identity_key(conflict.get("actual")):
            return [f"{path}: identity-mismatch requires unequal identities"]
    elif kind == "result-identity-mismatch":
        if identity_key(conflict.get("declared")) == identity_key(conflict.get("actual")):
            return [f"{path}: result-identity-mismatch requires unequal identities"]
    elif kind == "range-out-of-bounds":
        range_value = conflict.get("range")
        content_length = conflict.get("contentLength")
        if (
            isinstance(range_value, dict)
            and type(range_value.get("end")) is int
            and type(content_length) is int
            and range_value["end"] <= content_length
        ):
            return [f"{path}: range does not exceed contentLength"]
    elif kind == "overlapping-edits":
        left = conflict.get("left")
        right = conflict.get("right")
        if isinstance(left, dict) and isinstance(right, dict):
            values = [left.get("start"), left.get("end"), right.get("start"), right.get("end")]
            if all(type(value) is int for value in values):
                if left["end"] <= right["start"] or right["end"] <= left["start"]:
                    return [f"{path}: ranges do not overlap"]
    return []

def patch_errors(patch, path: str) -> list[str]:
    if not isinstance(patch, dict) or patch.get("operation") != "create":
        return []
    content = patch.get("content")
    identity = patch.get("resultingContentIdentity")
    if not isinstance(content, str) or not isinstance(identity, dict):
        return []
    encoded = content.encode("utf-8")
    actual = {
        "hash": "sha256:" + hashlib.sha256(encoded).hexdigest(),
        "size": len(encoded),
    }
    if identity_key(identity) != identity_key(actual):
        return [f"{path}: create content does not match resulting identity"]
    return []


def apply_internal_failure_errors(result) -> list[str]:
    if result.get("command") != "apply" or result.get("status") != "internal-error":
        return []
    summary = result.get("summary")
    if not isinstance(summary, dict):
        return ["$.summary: apply internal-error requires a failure summary"]
    allowed_fields = {"errorCode", "operation", "location", "commitState"}
    errors = []
    if set(summary) - allowed_fields:
        errors.append("$.summary: apply internal-error has unknown fields")
    if summary.get("errorCode") not in APPLY_INTERNAL_ERROR_CODES:
        errors.append("$.summary.errorCode: unknown apply internal error code")
    if summary.get("operation") not in APPLY_INTERNAL_OPERATIONS:
        errors.append("$.summary.operation: unknown apply internal operation")
    location = summary.get("location")
    if not isinstance(location, str) or not location:
        errors.append("$.summary.location: workspace-relative location is required")
    if "commitState" in summary and summary["commitState"] not in {
        "not-committed",
        "committed-or-unknown",
    }:
        errors.append("$.summary.commitState: unknown commit state")
    return errors


def scoped_id_key(value):
    if not isinstance(value, dict):
        return None
    artifact = value.get("artifact")
    local = value.get("local")
    if not isinstance(artifact, str) or not isinstance(local, str):
        return None
    return artifact, local


def observation_errors(result) -> list[str]:
    errors = []
    artifacts = {
        artifact.get("id")
        for artifact in result.get("artifacts", [])
        if isinstance(artifact, dict) and isinstance(artifact.get("id"), str)
    }
    collection_specs = [
        ("regions", "region"),
        ("references", "reference"),
        ("annotations", "annotation"),
    ]
    ids = {}
    for collection, label in collection_specs:
        keys = [
            scoped_id_key(value.get("id"))
            for value in result.get(collection, [])
            if isinstance(value, dict)
        ]
        concrete = [key for key in keys if key is not None]
        if len(concrete) != len(set(concrete)):
            errors.append(f"$.{collection}: {label} IDs must be unique")
        for index, key in enumerate(keys):
            if key is not None and key[0] not in artifacts:
                errors.append(
                    f"$.{collection}[{index}].id.artifact: parent artifact is absent"
                )
        ids[collection] = set(concrete)

    def check_region_ref(value, path: str):
        if not isinstance(value, dict) or value.get("kind") != "resolved":
            return
        key = scoped_id_key(value.get("id"))
        if key is not None and key not in ids["regions"]:
            errors.append(f"{path}: resolved region is absent")

    for index, annotation in enumerate(result.get("annotations", [])):
        if not isinstance(annotation, dict):
            continue
        check_region_ref(annotation.get("subject"), f"$.annotations[{index}].subject")
        object_value = annotation.get("object")
        if not isinstance(object_value, dict):
            continue
        if object_value.get("kind") == "region":
            check_region_ref(
                object_value.get("region"),
                f"$.annotations[{index}].object.region",
            )
        elif object_value.get("kind") == "reference":
            key = scoped_id_key(object_value.get("reference"))
            if key is not None and key not in ids["references"]:
                errors.append(
                    f"$.annotations[{index}].object.reference: reference is absent"
                )

    for index, diagnostic in enumerate(result.get("diagnostics", [])):
        if not isinstance(diagnostic, dict):
            continue
        location = diagnostic.get("location")
        if not isinstance(location, dict):
            continue
        scopes = []
        if isinstance(location.get("artifact"), str):
            scopes.append(location["artifact"])
        for field in ("region", "annotation"):
            key = scoped_id_key(location.get(field))
            if key is not None:
                scopes.append(key[0])
        if scopes and any(scope != scopes[0] for scope in scopes[1:]):
            errors.append(
                f"$.diagnostics[{index}].location: scoped IDs disagree on artifact"
            )
    return errors


def capability_errors(result) -> list[str]:
    identities = []
    for capability in result.get("capabilities", []):
        if not isinstance(capability, dict):
            continue
        identity = (
            capability.get("type"),
            capability.get("name"),
            capability.get("version"),
        )
        if all(isinstance(value, str) for value in identity):
            identities.append(identity)
    if len(identities) != len(set(identities)):
        return ["$.capabilities: capability identities must be unique"]
    return []

def patch_identity_errors(result) -> list[str]:
    identifiers = [
        patch.get("id")
        for patch in result.get("patches", [])
        if isinstance(patch, dict) and isinstance(patch.get("id"), str)
    ]
    if len(identifiers) != len(set(identifiers)):
        return ["$.patches: patch IDs must be unique"]
    return []


def semantic_errors(result) -> list[str]:
    errors = [
        f"{path}: integral protocol values must use JSON integer syntax"
        for path, value in walk_json(result)
        if isinstance(value, float)
    ]
    for path, value in command_result_ranges(result):
        if not isinstance(value, dict):
            continue
        start = value.get("start")
        end = value.get("end")
        if type(start) is int and type(end) is int and end < start:
            errors.append(f"{path}: range end must not precede start")
    for index, conflict in enumerate(result.get("conflicts", [])):
        errors.extend(conflict_errors(conflict, f"$.conflicts[{index}]"))
    for path, patch in command_result_patches(result):
        errors.extend(patch_errors(patch, path))
    errors.extend(apply_internal_failure_errors(result))
    errors.extend(observation_errors(result))
    errors.extend(capability_errors(result))
    errors.extend(patch_identity_errors(result))
    return errors


def main(arguments: list[str]) -> int:
    if not arguments:
        print("usage: semantic_contract.py <command-result.json>...", file=sys.stderr)
        return 2
    failed = False
    for argument in arguments:
        try:
            value = strict_json_load(Path(argument), display_path=argument)
        except ContractJsonError as error:
            print(error, file=sys.stderr)
            failed = True
            continue
        errors = semantic_errors(value)
        for error in errors:
            print(f"{argument}: {error}", file=sys.stderr)
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

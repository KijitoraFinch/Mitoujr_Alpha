#!/usr/bin/env python3
"""Validate semantic constraints not expressible in JSON Schema."""

from __future__ import annotations

import hashlib
import json
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
PROTOCOL_MAXIMUM_SAFE_INTEGER = 9_007_199_254_740_991


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


def observation_scoped_id_key(value):
    if not isinstance(value, dict):
        return None
    observation = value.get("observation")
    local = value.get("local")
    if not isinstance(observation, str) or not isinstance(local, str):
        return None
    return observation, local


def origin_key(value):
    if not isinstance(value, dict):
        return None
    return json.dumps(
        value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    )


def origin_scoped_id_key(value):
    if not isinstance(value, dict):
        return None
    scope = origin_key(value.get("scope"))
    local = value.get("local")
    if scope is None or not isinstance(local, str):
        return None
    return scope, local


def observation_errors(result) -> list[str]:
    errors = []
    observations = {
        observation.get("id")
        for observation in result.get("observations", [])
        if isinstance(observation, dict)
        and isinstance(observation.get("id"), str)
    }
    collection_specs = [
        ("regions", "region", observation_scoped_id_key),
        ("references", "reference", origin_scoped_id_key),
        ("annotations", "annotation", origin_scoped_id_key),
    ]
    ids = {}
    for collection, label, key_of in collection_specs:
        keys = [
            key_of(value.get("id"))
            for value in result.get(collection, [])
            if isinstance(value, dict)
        ]
        concrete = [key for key in keys if key is not None]
        if len(concrete) != len(set(concrete)):
            errors.append(f"$.{collection}: {label} IDs must be unique")
        if collection == "regions":
            for index, key in enumerate(keys):
                if key is not None and key[0] not in observations:
                    errors.append(
                        f"$.{collection}[{index}].id.observation: parent observation is absent"
                    )
        ids[collection] = set(concrete)

    def check_region_ref(value, path: str):
        if not isinstance(value, dict) or value.get("kind") != "resolved":
            return
        key = observation_scoped_id_key(value.get("id"))
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
    observation_origins = {
        observation.get("id"): origin_key(observation.get("origin"))
        for observation in result.get("observations", [])
        if isinstance(observation, dict)
        and isinstance(observation.get("id"), str)
    }
    for index, diagnostic in enumerate(result.get("diagnostics", [])):
        if not isinstance(diagnostic, dict):
            continue
        location = diagnostic.get("location")
        if not isinstance(location, dict):
            continue
        observation_scopes = []
        origin_scopes = []
        if isinstance(location.get("observation"), str):
            observation_scopes.append(location["observation"])
        region = observation_scoped_id_key(location.get("region"))
        if region is not None:
            observation_scopes.append(region[0])
        annotation = origin_scoped_id_key(location.get("annotation"))
        if annotation is not None:
            origin_scopes.append(annotation[0])
        origin_scopes.extend(
            observation_origins.get(scope)
            for scope in observation_scopes
            if observation_origins.get(scope) is not None
        )
        observations_disagree = observation_scopes and any(
            scope != observation_scopes[0] for scope in observation_scopes[1:]
        )
        origins_disagree = origin_scopes and any(
            scope != origin_scopes[0] for scope in origin_scopes[1:]
        )
        if observations_disagree or origins_disagree:
            errors.append(
                f"$.diagnostics[{index}].location: scoped IDs disagree on observation"
            )
    return errors


def capability_errors(result) -> list[str]:
    identities = []
    errors = []
    for index, capability in enumerate(result.get("capabilities", [])):
        if not isinstance(capability, dict):
            continue
        identity = (
            capability.get("type"),
            capability.get("name"),
            capability.get("version"),
        )
        if all(isinstance(value, str) for value in identity):
            identities.append(identity)
        applicability = capability.get("applicability")
        if not isinstance(applicability, dict):
            continue
        path_globs = applicability.get("pathGlobs")
        if not isinstance(path_globs, list):
            continue
        for glob_index, pattern in enumerate(path_globs):
            if not isinstance(pattern, str):
                continue
            segments = pattern.split("/")
            invalid = (
                not pattern
                or pattern.startswith("/")
                or pattern.endswith("/")
                or any(segment in {"", ".", ".."} for segment in segments)
                or any(
                    any(character in segment for character in "?[]\\\0")
                    or ("**" in segment and segment != "**")
                    for segment in segments
                )
            )
            if invalid:
                errors.append(
                    f"$.capabilities[{index}].applicability.pathGlobs[{glob_index}]: "
                    "invalid path glob"
                )
    if len(identities) != len(set(identities)):
        errors.append("$.capabilities: capability identities must be unique")
    return errors

def patch_identity_errors(result) -> list[str]:
    identifiers = [
        patch.get("id")
        for patch in result.get("patches", [])
        if isinstance(patch, dict) and isinstance(patch.get("id"), str)
    ]
    if len(identifiers) != len(set(identifiers)):
        return ["$.patches: patch IDs must be unique"]
    return []


def resolve_output_errors(result) -> list[str]:
    if result.get("command") != "resolve":
        return []
    errors = []
    observations = result.get("observations", [])
    regions = result.get("regions", [])
    for index, snapshot in enumerate(result.get("snapshots", [])):
        if not isinstance(snapshot, dict):
            continue
        target = snapshot.get("target")
        if not isinstance(target, dict):
            continue
        matching_observations = [
            observation
            for observation in observations
            if isinstance(observation, dict)
            and observation.get("origin") == target.get("origin")
            and observation.get("identity") == snapshot.get("observationIdentity")
        ]
        if len(matching_observations) != 1:
            errors.append(
                f"$.snapshots[{index}]: exactly one fixed target Observation is required"
            )
            continue
        observation_id = matching_observations[0].get("id")
        matching_regions = [
            region
            for region in regions
            if isinstance(region, dict)
            and observation_scoped_id_key(region.get("id")) is not None
            and observation_scoped_id_key(region.get("id"))[0] == observation_id
            and region.get("selector") == target.get("selector")
            and region.get("interpreter") == target.get("interpreter")
            and region.get("interpreterVersion")
            == target.get("interpreterVersion")
        ]
        if len(matching_regions) != 1:
            errors.append(
                f"$.snapshots[{index}]: exactly one resolved target Region is required"
            )
    return errors


def semantic_errors(result) -> list[str]:
    errors = [
        f"{path}: integral protocol values must use JSON integer syntax"
        for path, value in walk_json(result)
        if isinstance(value, float)
    ]
    errors.extend(
        f"{path}: integer exceeds the protocol safe-integer range"
        for path, value in walk_json(result)
        if type(value) is int and abs(value) > PROTOCOL_MAXIMUM_SAFE_INTEGER
    )
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
    errors.extend(resolve_output_errors(result))
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

"""Strict JSON parsing and typed comparison for specification checks."""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any


class ContractJsonError(ValueError):
    """Raised when input is not an unambiguous RFC JSON value."""


def _object_without_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ContractJsonError(f"duplicate object key: {key!r}")
        result[key] = value
    return result


def _reject_non_finite(value: str) -> None:
    raise ContractJsonError(f"non-finite number is not JSON: {value}")


def _finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ContractJsonError(f"number exceeds the finite float range: {value}")
    return parsed


def _require_unicode_scalars(value: Any, path: str = "$") -> None:
    if isinstance(value, str):
        try:
            value.encode("utf-8")
        except UnicodeEncodeError as error:
            raise ContractJsonError(
                f"{path}: string contains a non-scalar Unicode value"
            ) from error
    elif isinstance(value, dict):
        for key, child in value.items():
            _require_unicode_scalars(key, f"{path}.<key>")
            _require_unicode_scalars(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _require_unicode_scalars(child, f"{path}[{index}]")


def loads(text: str, *, source: str) -> Any:
    """Parse JSON while rejecting duplicate keys and non-finite numbers."""

    try:
        value = json.loads(
            text,
            object_pairs_hook=_object_without_duplicates,
            parse_constant=_reject_non_finite,
            parse_float=_finite_float,
        )
        _require_unicode_scalars(value)
        return value
    except (json.JSONDecodeError, ContractJsonError) as error:
        raise ContractJsonError(f"{source}: {error}") from error


def load(path: Path, *, display_path: str | None = None) -> Any:
    source = display_path if display_path is not None else str(path)
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ContractJsonError(f"{source}: {error}") from error
    return loads(text, source=source)


def equal_exact(left: Any, right: Any) -> bool:
    """Compare JSON values without Python's bool/int/float coercions.

    Object member order is included because normal-form encoders promise a
    deterministic order even though ordinary JSON semantics do not require it.
    """

    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        if list(left) != list(right):
            return False
        return all(equal_exact(left[key], right[key]) for key in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(
            equal_exact(left_value, right_value)
            for left_value, right_value in zip(left, right, strict=True)
        )
    return bool(left == right)

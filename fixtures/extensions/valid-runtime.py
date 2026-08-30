from __future__ import annotations

import base64
import json
import sys


CAPABILITY = {
    "type": "interpreter",
    "name": "custom-markdown",
    "version": "1",
    "appliesTo": {
        "mediaTypes": ["text/markdown"],
        "pathGlobs": ["docs/*.md"],
    },
    "schemas": {
        "selector": (
            "https://example.invalid/schemas/"
            "custom-markdown-selector-v1.json"
        )
    },
}

REFERENCE_CAPABILITY = {
    "type": "reference-extractor",
    "name": "custom-markdown-references",
    "version": "1",
    "appliesTo": {
        "mediaTypes": ["text/markdown"],
        "pathGlobs": ["docs/*.md"],
    },
}

RESOLVE_CAPABILITY = {
    **CAPABILITY,
    "appliesTo": {
        "mediaTypes": ["text/x-custom-markdown"],
        "pathGlobs": ["docs/*.custom"],
    },
}

RESOLVE_REFERENCE_CAPABILITY = {
    **REFERENCE_CAPABILITY,
    "appliesTo": {
        "mediaTypes": ["text/x-custom-markdown"],
        "pathGlobs": ["docs/*.custom"],
    },
}


def receive_content(request: dict, lines) -> bytes:
    descriptor = request["params"]["content"]
    if descriptor.get("kind") != "byteStream":
        raise ValueError("content is not a byte stream")
    expected_length = descriptor.get("byteLength")
    offset = 0
    chunks: list[bytes] = []
    for line in lines:
        notification = json.loads(line)
        params = notification.get("params", {})
        if params.get("requestId") != request["id"]:
            raise ValueError("content notification has the wrong request ID")
        if notification.get("method") == "monika.contentChunk":
            if params.get("offset") != offset:
                raise ValueError("content chunk is out of order")
            chunk = base64.b64decode(params.get("base64", ""), validate=True)
            chunks.append(chunk)
            offset += len(chunk)
        elif notification.get("method") == "monika.endContent":
            if params.get("byteLength") != offset or offset != expected_length:
                raise ValueError("content byte length does not match")
            return b"".join(chunks)
        else:
            raise ValueError("unexpected message while receiving content")
    raise ValueError("content stream ended before its terminator")


def interpretation_result(
    request: dict, content: bytes, *, expected_observation_type: str
) -> dict:
    params = request["params"]
    observation = params["observation"]
    if observation["identity"]["observationType"] != {
        "name": expected_observation_type,
        "version": "1",
    }:
        raise ValueError("host passed an observation with the wrong fixed type")
    selector_schema = CAPABILITY["schemas"]["selector"]
    length = len(content)
    return {
        "jsonrpc": "2.0",
        "id": request["id"],
        "result": {
            "interpretation": {
                "interpreter": {
                    "name": CAPABILITY["name"],
                    "version": CAPABILITY["version"],
                },
                "observation": observation["id"],
                "regions": [
                    {
                        "id": {
                            "observation": observation["id"],
                            "local": "extension:document",
                        },
                        "selector": {
                            "kind": "extension",
                            "schema": selector_schema,
                            "value": {"kind": "document"},
                        },
                        "summary": "extension interpreted document",
                        "range": {"start": 0, "end": length},
                        "fingerprint": observation["contentIdentity"]["hash"],
                    }
                ],
            }
        },
    }


def reference_extraction_result(request: dict) -> dict:
    observation = request["params"]["observation"]
    definitions = []
    if observation["origin"].get("path") in {"docs/source.md", "docs/source.custom"}:
        definitions.append(
            {
                "id": {
                    "observation": observation["id"],
                    "local": "extension-target",
                },
                "target": {
                    "origin": {
                        "kind": "workspace",
                        "path": (
                            "docs/target.custom"
                            if observation["origin"].get("path") == "docs/source.custom"
                            else "docs/target.md"
                        ),
                    },
                    "selector": {
                        "kind": "extension",
                        "schema": CAPABILITY["schemas"]["selector"],
                        "value": {"kind": "document"},
                    },
                    "interpreter": CAPABILITY["name"],
                    "interpreterVersion": CAPABILITY["version"],
                },
                "binding": "tracking",
                "expectations": [],
                "provenance": [{"source": "extension:custom-markdown-references"}],
            }
        )
    return {
        "jsonrpc": "2.0",
        "id": request["id"],
        "result": {"extraction": {"definitions": definitions, "uses": []}},
    }


def resolve_region_result(request: dict, content: bytes) -> dict:
    params = request["params"]
    observation = params["observation"]
    selector = params["selector"]
    selector_schema = CAPABILITY["schemas"]["selector"]
    expected_selector = {
        "kind": "extension",
        "schema": selector_schema,
        "value": {"kind": "document"},
    }
    if selector != expected_selector:
        result = {
            "failure": {
                "code": "invalid-selector",
                "message": "selector does not identify a document",
            }
        }
    else:
        result = {
            "region": {
                "id": {
                    "observation": observation["id"],
                    "local": "extension:document",
                },
                "selector": selector,
                "summary": "extension resolved document",
                "range": {"start": 0, "end": len(content)},
                "fingerprint": observation["contentIdentity"]["hash"],
            }
        }
    return {"jsonrpc": "2.0", "id": request["id"], "result": result}


def classify_region_extents_result(request: dict) -> dict:
    left = request["params"]["left"].get("range")
    right = request["params"]["right"].get("range")
    if left is None or right is None:
        result = {
            "failure": {
                "code": "extent-unavailable",
                "message": "both regions require an extent",
            }
        }
    elif left == right:
        result = {"relation": "equal"}
    elif left["start"] <= right["start"] and right["end"] <= left["end"]:
        result = {"relation": "contains"}
    elif right["start"] <= left["start"] and left["end"] <= right["end"]:
        result = {"relation": "contained-by"}
    elif left["start"] < right["end"] and right["start"] < left["end"]:
        result = {"relation": "overlaps"}
    else:
        result = {"relation": "disjoint"}
    return {"jsonrpc": "2.0", "id": request["id"], "result": result}


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) == 2 else "normal"
    if mode not in {
        "normal",
        "references",
        "resolve",
        "resolve-references",
        "initialize-failure",
        "interpret-failure",
    }:
        raise ValueError(f"unknown fixture mode: {mode}")
    lines = iter(sys.stdin)
    for line in lines:
        request = json.loads(line)
        if request.get("method") == "monika.initializeSession":
            if mode == "initialize-failure":
                response = {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "error": {
                        "code": -32003,
                        "message": "runtime is unavailable",
                        "data": {"retryable": False},
                    },
                }
            else:
                active_capability = {
                    "references": REFERENCE_CAPABILITY,
                    "resolve": RESOLVE_CAPABILITY,
                    "resolve-references": RESOLVE_REFERENCE_CAPABILITY,
                }.get(mode, CAPABILITY)
                response = {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "protocolVersion": "1",
                        "capability": active_capability,
                        "maxMessageBytes": 16 * 1024 * 1024,
                    },
                }
        elif request.get("method") == "monika.interpretObservation":
            content = receive_content(request, lines)
            if mode == "interpret-failure":
                response = {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "failure": {
                            "code": "parser-unavailable",
                            "message": "parser is unavailable",
                            "data": {"retryable": True},
                        }
                    },
                }
            else:
                response = interpretation_result(
                    request,
                    content,
                    expected_observation_type=(
                        "text/x-custom-markdown" if mode == "resolve" else "text/markdown"
                    ),
                )
        elif request.get("method") == "monika.resolveRegion":
            content = receive_content(request, lines)
            response = resolve_region_result(request, content)
        elif request.get("method") == "monika.extractReferences":
            receive_content(request, lines)
            if mode not in {"references", "resolve-references"}:
                raise ValueError("reference extraction used the wrong session")
            response = reference_extraction_result(request)
        elif request.get("method") == "monika.classifyRegionExtents":
            receive_content(request, lines)
            response = classify_region_extents_result(request)
        else:
            response = {
                "jsonrpc": "2.0",
                "id": request.get("id"),
                "error": {"code": -32601, "message": "method not found"},
            }
        print(json.dumps(response, ensure_ascii=False, separators=(",", ":")))
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

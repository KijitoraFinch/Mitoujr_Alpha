from __future__ import annotations

import base64
import json
import sys


CAPABILITY = {
    "type": "interpreter",
    "name": "example-relations",
    "version": "1",
    "appliesTo": {
        "mediaTypes": ["text/x-example"],
        "pathGlobs": ["**/*.example"],
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


def scoped(observation: str, local: str) -> dict:
    return {"observation": observation, "local": local}


def region(observation: dict, local: str, length: int) -> dict:
    return {
        "id": scoped(observation["id"], local),
        "selector": {"kind": "region-id", "id": local},
        "summary": local,
        "range": {"start": 0, "end": length},
        "fingerprint": observation["contentIdentity"]["hash"],
    }


def interpretation_result(request: dict, content: bytes) -> dict:
    observation = request["params"]["observation"]
    if observation["identity"]["observationType"] != {
        "name": "text/x-example",
        "version": "1",
    }:
        raise ValueError("host passed an observation with the wrong fixed type")
    path = observation["origin"]["path"]
    length = len(content)
    regions = []
    references = []
    annotations = []
    if path == "source.example":
        regions.append(region(observation, "source", length))
        reference_id = scoped(observation["id"], "target")
        references.append(
            {
                "id": reference_id,
                "target": {
                    "origin": {
                        "kind": "workspace",
                        "path": "target.example",
                    },
                    "selector": {"kind": "region-id", "id": "target"},
                    "interpreter": CAPABILITY["name"],
                    "interpreterVersion": CAPABILITY["version"],
                },
                "binding": "tracking",
                "expectations": [],
                "provenance": [{"source": "extension:example-relations"}],
            }
        )
        annotations.append(
            {
                "id": scoped(observation["id"], "source-depends-on-target"),
                "subject": {
                    "kind": "resolved",
                    "id": scoped(observation["id"], "source"),
                },
                "predicate": "depends-on",
                "object": {"kind": "reference", "reference": reference_id},
                "provenance": [{"source": "extension:example-relations"}],
                "materialization": [],
            }
        )
    elif path == "target.example":
        regions.append(region(observation, "target", length))
    else:
        raise ValueError("host dispatched an inapplicable observation")
    return {
        "jsonrpc": "2.0",
        "id": request["id"],
        "result": {
            "interpretation": {
                "regions": regions,
                "references": references,
                "annotations": annotations,
            }
        },
    }


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
    if mode not in {"normal", "initialize-failure", "interpret-failure"}:
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
                response = {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "protocolVersion": "1",
                        "capability": CAPABILITY,
                        "maxMessageBytes": 16 * 1024 * 1024,
                    },
                }
        elif request.get("method") == "monika.interpretObservation":
            content = receive_content(request, lines)
            path = request["params"]["observation"]["origin"]["path"]
            if mode == "interpret-failure":
                response = {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "result": {
                        "failure": {
                            "code": "parser-unavailable",
                            "message": f"parser is unavailable for {path}",
                            "data": {"path": path},
                        }
                    },
                }
            else:
                response = interpretation_result(request, content)
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

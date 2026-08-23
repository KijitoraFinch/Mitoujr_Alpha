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


def content_length(content: dict) -> int:
    if content.get("kind") == "inlineText":
        return len(content["text"].encode("utf-8"))
    if content.get("kind") == "inlineBase64":
        return len(base64.b64decode(content["base64"], validate=True))
    raise ValueError("unsupported content kind")


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


def interpretation_result(request: dict) -> dict:
    observation = request["params"]["observation"]
    if observation["identity"]["observationType"] != {
        "name": "text/x-example",
        "version": "1",
    }:
        raise ValueError("host passed an observation with the wrong fixed type")
    path = observation["origin"]["path"]
    length = content_length(request["params"]["content"])
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


def main() -> int:
    interpreted_paths: set[str] = set()
    for line in sys.stdin:
        request = json.loads(line)
        if request.get("method") == "monika.initializeSession":
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
            path = request["params"]["observation"]["origin"]["path"]
            if path == "target.example" and "source.example" not in interpreted_paths:
                response = {
                    "jsonrpc": "2.0",
                    "id": request["id"],
                    "error": {
                        "code": -32600,
                        "message": "source and target were not interpreted in one session",
                    },
                }
            else:
                response = interpretation_result(request)
                interpreted_paths.add(path)
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

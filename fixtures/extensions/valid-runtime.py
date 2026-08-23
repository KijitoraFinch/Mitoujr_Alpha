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


def content_length(content: dict) -> int:
    if content.get("kind") == "inlineText":
        return len(content.get("text", "").encode("utf-8"))
    if content.get("kind") == "inlineBase64":
        return len(base64.b64decode(content.get("base64", ""), validate=True))
    raise ValueError("unsupported content kind")


def interpretation_result(request: dict) -> dict:
    params = request["params"]
    observation = params["observation"]
    if observation["identity"]["observationType"] != {
        "name": "text/markdown",
        "version": "1",
    }:
        raise ValueError("host passed an observation with the wrong fixed type")
    selector_schema = CAPABILITY["schemas"]["selector"]
    length = content_length(params["content"])
    path = observation["origin"].get("path")
    references = []
    if path == "docs/source.md":
        references.append(
            {
                "id": {
                    "observation": observation["id"],
                    "local": "extension-target",
                },
                "target": {
                    "origin": {
                        "kind": "workspace",
                        "path": "docs/target.md",
                    },
                    "selector": {
                        "kind": "extension",
                        "schema": selector_schema,
                        "value": {"kind": "document"},
                    },
                    "interpreter": CAPABILITY["name"],
                    "interpreterVersion": CAPABILITY["version"],
                },
                "binding": "tracking",
                "expectations": [],
                "provenance": [{"source": "extension:custom-markdown"}],
            }
        )
    return {
        "jsonrpc": "2.0",
        "id": request["id"],
        "result": {
            "interpretation": {
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
                "references": references,
                "annotations": [],
            }
        },
    }


def resolve_region_result(request: dict) -> dict:
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
                "range": {"start": 0, "end": content_length(params["content"])},
                "fingerprint": observation["contentIdentity"]["hash"],
            }
        }
    return {"jsonrpc": "2.0", "id": request["id"], "result": result}


def main() -> int:
    source_reference_interpreted = False
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
            response = interpretation_result(request)
            observation_path = request["params"]["observation"]["origin"].get("path")
            if observation_path == "docs/source.md":
                source_reference_interpreted = True
        elif request.get("method") == "monika.resolveRegion":
            if source_reference_interpreted:
                response = resolve_region_result(request)
            else:
                response = {
                    "jsonrpc": "2.0",
                    "id": request.get("id"),
                    "error": {
                        "code": -32600,
                        "message": "source observation was not interpreted in this session",
                    },
                }
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

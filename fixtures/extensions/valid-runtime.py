from __future__ import annotations

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
        return len(content.get("text", ""))
    if content.get("kind") == "inlineBase64":
        return 0
    return 0


def observe_result(request: dict) -> dict:
    params = request["params"]
    artifact = params["artifact"]
    selector_schema = CAPABILITY["schemas"]["selector"]
    length = content_length(params["content"])
    path = artifact["origin"].get("path")
    references = []
    if path == "docs/source.md":
        references.append(
            {
                "id": {
                    "artifact": artifact["id"],
                    "local": "extension-target",
                },
                "target": {
                    "artifact": {
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
            "observation": {
                "artifacts": [],
                "regions": [
                    {
                        "id": {
                            "artifact": artifact["id"],
                            "local": "extension:document",
                        },
                        "selector": {
                            "kind": "extension",
                            "schema": selector_schema,
                            "value": {"kind": "document"},
                        },
                        "summary": "extension observed document",
                        "range": {"start": 0, "end": length},
                        "fingerprint": artifact["contentIdentity"]["hash"],
                    }
                ],
                "references": references,
                "annotations": [],
            }
        },
    }


def resolve_region_result(request: dict) -> dict:
    params = request["params"]
    artifact = params["artifact"]
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
                    "artifact": artifact["id"],
                    "local": "extension:document",
                },
                "selector": selector,
                "summary": "extension resolved document",
                "range": {"start": 0, "end": content_length(params["content"])},
                "fingerprint": artifact["contentIdentity"]["hash"],
            }
        }
    return {"jsonrpc": "2.0", "id": request["id"], "result": result}


def main() -> int:
    source_reference_observed = False
    for line in sys.stdin:
        request = json.loads(line)
        if request.get("method") == "monika.describe":
            response = {
                "jsonrpc": "2.0",
                "id": request["id"],
                "result": {
                    "protocolVersion": "1",
                    "capability": CAPABILITY,
                    "maxMessageBytes": 16 * 1024 * 1024,
                },
            }
        elif request.get("method") == "monika.observe":
            response = observe_result(request)
            artifact_path = request["params"]["artifact"]["origin"].get("path")
            if artifact_path == "docs/source.md":
                source_reference_observed = True
        elif request.get("method") == "monika.resolveRegion":
            if source_reference_observed:
                response = resolve_region_result(request)
            else:
                response = {
                    "jsonrpc": "2.0",
                    "id": request.get("id"),
                    "error": {
                        "code": -32600,
                        "message": "source reference was not observed in this session",
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

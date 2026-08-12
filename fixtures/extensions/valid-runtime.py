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
                "references": [],
                "annotations": [],
            }
        },
    }


def main() -> int:
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

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


def main() -> int:
    for line in sys.stdin:
        request = json.loads(line)
        if request.get("method") != "monika.describe":
            response = {
                "jsonrpc": "2.0",
                "id": request.get("id"),
                "error": {"code": -32601, "message": "method not found"},
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
        print(json.dumps(response, ensure_ascii=False, separators=(",", ":")))
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

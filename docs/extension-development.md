# 外部 extension の作成方法

## 現在検証できる範囲

現在の `monika extension test` は、外部プロセスの起動、stdio 上の JSON-RPC 通信、
protocol version、および capability の一致を検証します。さらに `monika inspect` は、
CLI で指定された一時的な interpreter extension を起動し、
`monika.interpretObservation` の結果を
CommandResult に取り込めます。

`monika related` は明示指定または installed registry を workspace graph 構築へ追加し、
applicability に一致する Observation を独立した checked session で解釈します。

`monika resolve` は source の `monika.interpretObservation` と target Interpreter の
`monika.resolveRegion` を独立した checked session で呼びます。

registry 内の適用可能な Reference Extractor は `monika.extractReferences` を独立した
checked session で実行し、その定義と use occurrence を加算します。

protocol version 1 で通常コマンドから実行する capability は `interpreter` と
`reference-extractor` です。Resource Observer、annotation extractor、deriver、auditor、
renderer、および indexer は identity を検査できますが、それぞれの runtime method が
定義されるまで通常コマンドから呼び出しません。
`capability.schemas` で使用できる field も、現在の method が参照する `selector` だけです。

## 必要なファイル

次の二つを用意します。

- capability を記述した JSON manifest
- stdin から request を読み、stdout へ response を返す executable

manifest に executable path や引数は書きません。実行時に CLI で指定します。

```json
{
  "protocolVersion": "1",
  "capability": {
    "type": "interpreter",
    "name": "example-language",
    "version": "1",
    "appliesTo": {
      "mediaTypes": ["text/x-example"],
      "pathGlobs": ["**/*.example"]
    },
    "schemas": {
      "selector": "https://example.com/schemas/example-selector-v1.json"
    }
  }
}
```

`name` と `version` は解釈規則の識別に使用します。既存の Selector に対する解決結果が
変わる場合は、同じ名前の新しい version にします。`schemas.selector` は、その
interpreter が受け取る extension Selector の JSON Schema を指します。

## Python による process の例

以下の process は `monika.initializeSession`、`monika.interpretObservation`、
`monika.resolveRegion`、および `monika.classifyRegionExtents` に応答します。
ほかの実装言語でも、同じ byte 列を入出力すれば
動作は同じです。

```python
import base64
import json
import sys

CAPABILITY = {
    "type": "interpreter",
    "name": "example-language",
    "version": "1",
    "appliesTo": {
        "mediaTypes": ["text/x-example"],
        "pathGlobs": ["**/*.example"],
    },
    "schemas": {
        "selector": "https://example.com/schemas/example-selector-v1.json"
    },
}

def receive_content(request, lines):
    descriptor = request["params"]["content"]
    if descriptor["kind"] != "byteStream":
        raise ValueError("content is not a byte stream")
    chunks = []
    offset = 0
    for line in lines:
        notification = json.loads(line)
        params = notification["params"]
        if params["requestId"] != request["id"]:
            raise ValueError("wrong content request ID")
        if notification["method"] == "monika.contentChunk":
            if params["offset"] != offset:
                raise ValueError("out-of-order content chunk")
            chunk = base64.b64decode(params["base64"], validate=True)
            chunks.append(chunk)
            offset += len(chunk)
        elif notification["method"] == "monika.endContent":
            if params["byteLength"] != offset:
                raise ValueError("content length mismatch")
            if descriptor["byteLength"] != offset:
                raise ValueError("descriptor length mismatch")
            return b"".join(chunks)
        else:
            raise ValueError("unexpected content message")
    raise ValueError("content stream ended early")

def interpret_observation(request, content):
    params = request["params"]
    observation = params["observation"]
    byte_length = len(content)
    selector = {
        "kind": "extension",
        "schema": CAPABILITY["schemas"]["selector"],
        "value": {"kind": "document"},
    }
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
                            "local": "example:document",
                        },
                        "selector": selector,
                        "summary": "example document",
                        "range": {"start": 0, "end": byte_length},
                    }
                ],
            }
        },
    }

def resolve_region(request, content):
    params = request["params"]
    observation = params["observation"]
    byte_length = len(content)
    return {
        "jsonrpc": "2.0",
        "id": request["id"],
        "result": {
            "region": {
                "id": {
                    "observation": observation["id"],
                    "local": "example:document",
                },
                "selector": params["selector"],
                "summary": "example document",
                "range": {"start": 0, "end": byte_length},
            }
        },
    }

def classify_region_extents(request):
    left = request["params"]["left"]["range"]
    right = request["params"]["right"]["range"]
    if left == right:
        relation = "equal"
    elif left["start"] <= right["start"] and right["end"] <= left["end"]:
        relation = "contains"
    elif right["start"] <= left["start"] and left["end"] <= right["end"]:
        relation = "contained-by"
    elif left["start"] < right["end"] and right["start"] < left["end"]:
        relation = "overlaps"
    else:
        relation = "disjoint"
    return {
        "jsonrpc": "2.0",
        "id": request["id"],
        "result": {"relation": relation},
    }

lines = iter(sys.stdin)
for line in lines:
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
        response = interpret_observation(request, receive_content(request, lines))
    elif request.get("method") == "monika.resolveRegion":
        response = resolve_region(request, receive_content(request, lines))
    elif request.get("method") == "monika.classifyRegionExtents":
        receive_content(request, lines)
        response = classify_region_extents(request)
    else:
        response = {
            "jsonrpc": "2.0",
            "id": request.get("id"),
            "error": {"code": -32601, "message": "method not found"},
        }
    print(json.dumps(response, ensure_ascii=False, separators=(",", ":")))
    sys.stdout.flush()
```

一つの response を書くたびに stdout を flush してください。log は stderr へ書いて
ください。stdin が EOF になったら、終了 status `0` で終了してください。

## Range の単位

`range.start` と `range.end` は、入力 observation の正確な byte 列に対するゼロ起点の
半開区間 `[start, end)` です。Unicode code point 数や UTF-16 code unit 数ではなく、
byte stream から受信した byte 列を基準にします。

## 検証コマンド

```sh
monika extension test \
  --manifest extension.json \
  --executable python3 \
  --argument extension.py
```

引数が複数ある場合は、渡す順序で `--argument` を繰り返します。

```sh
monika extension test \
  --manifest extension.json \
  --executable node \
  --argument extension.js \
  --argument --strict
```

成功時は process exit code `0` になり、CommandResult の `summary.runtimeChecked` が
`true` になります。この検査は次を確認します。

- process を shell を介さずに起動できること
- `monika.initializeSession` request を30秒以内に処理できること
- response が JSON-RPC 2.0 と protocol の JSON 制約を満たすこと
- response の ID が request の ID と一致すること
- response の protocol version が `"1"` であること
- response の capability が静的 manifest と一致すること
- Monika と process の message size 上限を決定できること
- stdin の EOF 後1秒以内に status `0` で終了すること

静的 manifest だけを検証する場合は `--executable` を省略します。

```sh
monika extension test --manifest extension.json
```

## inspect からの一時利用

開発中の interpreter extension は、install や登録を行わずに `inspect` から実行できます。

```sh
monika inspect \
  --workspace . \
  --observation docs/example.md \
  --extension-manifest extension.json \
  --extension-executable python3 \
  --extension-argument extension.py
```

`--extension-argument` は指定順に何度でも使用できます。この一時指定は manifest を
workspace 設定へ保存せず、コマンド実行中の session だけに有効です。manifest の
capability は `interpreter` でなければなりません。既知の suffix は固定された media type
として照合します。未知の suffix を扱う場合は、`pathGlobs` で path を限定し、対応する
`mediaTypes` を一つ指定してください。適用条件に一致しない observation に extension を
実行することはできません。

## related からの一時利用

一つの明示的な extension を workspace graph の構築に追加できます。

```sh
monika related \
  --workspace . \
  --observation target.example \
  --direction incoming \
  --extension-manifest extension.json \
  --extension-executable python3 \
  --extension-argument extension.py
```

Monika は適用対象 Observation ごとに独立した checked session を使用します。
適用可能な Reference Extractor が返した use occurrence は incoming/outgoing edge に投影
されます。built-in Interpreter と適用範囲が重なる Interpreter manifest は曖昧として拒否されます。
extension が失敗した observation を built-in で解釈し直す fallback はありません。

## resolve からの一時利用

Reference Extractor が `monika.extractReferences` で宣言した reference は、target に記録した
Interpreter name/version の独立した session で `monika.resolveRegion` を実行して解決します。

```sh
monika resolve \
  --workspace . \
  --observation src/example.ext \
  --reference dependency \
  --observed-at 2026-08-13T00:00:00Z \
  --extension-registry registry.json
```

source observation の reference target は workspace origin でなければなりません。また、
target の interpreter name/version は manifest capability と一致し、extension selector の
schema は `capability.schemas.selector` と一致しなければなりません。返す region には、
request と同じ selector を使用してください。region の observation、content identity、
interpreter、および byte range は Monika が検査します。

source Interpreter、Reference Extractor、および target Interpreter を使う場合は、workspace 外に
installed registry snapshot を作り、
`--extension-registry` で指定します。registry は manifest と絶対 executable path、引数を
組にします。workspace の設定ファイルに executable や pipeline を書きません。

```json
{
  "schemaVersion": "1",
  "extensions": [
    {
      "manifest": {
        "protocolVersion": "1",
        "capability": {
          "type": "interpreter",
          "name": "example-language",
          "version": "1"
        }
      },
      "executable": "/absolute/path/to/python3",
      "arguments": ["/absolute/path/to/extension.py"]
    }
  ]
}
```

同じ capability type/name/version の重複、相対 executable path、および built-in
Interpreter identity との衝突は dispatch 前に拒否されます。

## 失敗時の確認

`extension test`、`inspect`、および `resolve` の Extension 実行が失敗した場合も、
Monika は `CommandResult` を stdout へ書きます。diagnostic の `extensionFailure.code` で
原因を、`extensionFailure.operation` で失敗した操作を区別できます。Extension が返した
任意の data も `extensionFailure.data` に保持されます。JSON-RPC error の数値 code は
`extensionFailure.data.jsonRpcCode` にあります。人が読む説明は diagnostic の
`message` にあります。

静的 manifest 自体が不正な場合は Extension を実行していないため、`invalid-input` と
`summary.message` を返します。この場合は `extensionFailure` を作りません。

`related` は専用の `RelatedResult` を返します。session の起動または初期化に失敗した
場合は `status` が `failed`、observation 単位の解釈に失敗した場合は `incomplete` になり、
同じ `diagnostics[].extensionFailure` から詳細を確認できます。

| code | 確認する箇所 |
|---|---|
| `spawn-failed` | executable path、実行権限、`PATH` |
| `pipe-failed` | operating system の process resource 上限 |
| `timeout` | stdin の読み取り、stdout の flush、処理時間 |
| `request-too-large` | 交渉後の `maxMessageBytes` |
| `response-too-large` | response の byte 数、不要な inline data |
| `invalid-response` | JSON、field、ID、protocol version、capability |
| `remote-error` | extension が返した JSON-RPC error |
| `process-exit` | EOF 後の終了 status、signal |
| `shutdown-timeout` | EOF を受け取った後も終了しない処理 |
| `manifest-mismatch` | process 内の capability と静的 manifest |

`write-failed`、`read-failed`、`unexpected-eof`、および
`process-wait-failed` は、process が通信途中で終了した場合や operating system の I/O が
失敗した場合に返ります。`invalid-command` は空文字または NUL を含む executable 指定、
`invalid-request` は Monika 内部で構築した method または params の不正、
`session-not-initialized` は `monika.initializeSession` より前の method 呼び出しを表します。
`request-id-exhausted` は、一つの session で使用できる request ID を使い切ったことを
表します。

## 実装時の確認事項

- stdout には一行の JSON response 以外を書かないでください。
- JSON object に同じ field name を複数回書かないでください。
- 小数を送らないでください。整数は JavaScript の safe integer の範囲内にしてください。
- JSON の array と object を128段より深く入れ子にしないでください。
- request ごとに同じ ID を response へコピーしてください。
- `monika.initializeSession` の result に、process が扱える正の `maxMessageBytes` を書いてください。
- `result` と `error` の一方だけを返してください。
- 受け取っていない method には JSON-RPC error を返してください。
- session をまたぐ必要がある状態を process 内に保存しないでください。
- workspace を直接変更しないでください。現在の runtime には書き込みを防ぐ sandbox が
  ないため、開発中の誤操作にも注意してください。
- `content` は常に `byteStream` です。`contentChunk` を offset 順に decode し、
  `endContent` の長さを検査してから response を返してください。
- すべての `range` はゼロ起点の半開 UTF-8 byte range です。文字数、Unicode code
  point 数、および UTF-16 code unit 数を使用しないでください。

完全な通信仕様は
[`protocol/extension-protocol.md`](../protocol/extension-protocol.md) を参照してください。
動作する Python の例は
[`fixtures/extensions/valid-runtime.py`](../fixtures/extensions/valid-runtime.py) にあります。

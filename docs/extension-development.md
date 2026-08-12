# 外部 extension の作成方法

## 現在検証できる範囲

現在の `monika extension test` は、外部プロセスの起動、stdio 上の JSON-RPC 通信、
protocol version、および capability の一致を検証します。さらに `monika inspect` は、
CLI で指定された一時的な interpreter extension を起動し、`monika.observe` の結果を
CommandResult に取り込めます。

`resolveRegion` の protocol は定義済みですが、通常の `monika resolve` から外部
extension へ dispatch する処理はまだ実装されていません。

## 必要なファイル

次の二つを用意します。

- capability を記述した JSON descriptor
- stdin から request を読み、stdout へ response を返す executable

descriptor に executable path や引数は書きません。実行時に CLI で指定します。

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

以下の process は `monika.describe` と `monika.observe` に応答します。ほかの実装言語
でも、同じ byte 列を入出力すれば動作は同じです。

```python
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

def observe(request):
    params = request["params"]
    artifact = params["artifact"]
    content = params["content"]
    text_length = len(content["text"]) if content["kind"] == "inlineText" else 0
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
                            "local": "example:document",
                        },
                        "selector": {
                            "kind": "extension",
                            "schema": CAPABILITY["schemas"]["selector"],
                            "value": {"kind": "document"},
                        },
                        "summary": "example document",
                        "range": {"start": 0, "end": text_length},
                    }
                ],
                "references": [],
                "annotations": [],
            }
        },
    }

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
        response = observe(request)
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

## 検証コマンド

```sh
monika extension test \
  --descriptor extension.json \
  --executable python3 \
  --argument extension.py
```

引数が複数ある場合は、渡す順序で `--argument` を繰り返します。

```sh
monika extension test \
  --descriptor extension.json \
  --executable node \
  --argument extension.js \
  --argument --strict
```

成功時は process exit code `0` になり、CommandResult の `summary.runtimeChecked` が
`true` になります。この検査は次を確認します。

- process を shell を介さずに起動できること
- `monika.describe` request を30秒以内に処理できること
- response が JSON-RPC 2.0 と protocol の JSON 制約を満たすこと
- response の ID が request の ID と一致すること
- response の protocol version が `"1"` であること
- response の capability が静的 descriptor と一致すること
- Monika と process の message size 上限を決定できること
- stdin の EOF 後1秒以内に status `0` で終了すること

静的 descriptor だけを検証する場合は `--executable` を省略します。

```sh
monika extension test --descriptor extension.json
```

## inspect からの一時利用

開発中の interpreter extension は、install や登録を行わずに `inspect` から実行できます。

```sh
monika inspect \
  --workspace . \
  --artifact docs/example.md \
  --extension-descriptor extension.json \
  --extension-executable python3 \
  --extension-argument extension.py
```

`--extension-argument` は指定順に何度でも使用できます。この一時指定は descriptor を
workspace 設定へ保存せず、コマンド実行中の session だけに有効です。descriptor の
capability は `interpreter` でなければなりません。参照実装はまだ media type 推定を
行わないため、`inspect` で使用する descriptor の `appliesTo.mediaTypes` は0個または
1個にしてください。1個の場合、その値を artifact の media type として extension に
渡します。

## 失敗時の確認

失敗時も、Monika は CommandResult を stdout へ書きます。`summary.message` の
`extension runtime` に続く code で原因を区別できます。

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
| `descriptor-mismatch` | process 内の capability と静的 descriptor |

`write-failed`、`read-failed`、`unexpected-eof`、および
`process-wait-failed` は、process が通信途中で終了した場合や operating system の I/O が
失敗した場合に返ります。`invalid-command` は空文字または NUL を含む executable 指定、
`invalid-request` は Monika 内部で構築した method または params の不正、
`describe-required` は `monika.describe` より前の method 呼び出しを表します。
`request-id-exhausted` は、一つの session で使用できる request ID を使い切ったことを
表します。

## 実装時の確認事項

- stdout には一行の JSON response 以外を書かないでください。
- JSON object に同じ field name を複数回書かないでください。
- 小数を送らないでください。整数は JavaScript の safe integer の範囲内にしてください。
- JSON の array と object を128段より深く入れ子にしないでください。
- request ごとに同じ ID を response へコピーしてください。
- `monika.describe` の result に、process が扱える正の `maxMessageBytes` を書いてください。
- `result` と `error` の一方だけを返してください。
- 受け取っていない method には JSON-RPC error を返してください。
- session をまたぐ必要がある状態を process 内に保存しないでください。
- workspace を直接変更しないでください。現在の runtime には書き込みを防ぐ sandbox が
  ないため、開発中の誤操作にも注意してください。
- `content.kind` が `inlineText` の場合だけ text として扱ってください。binary や未知の
 形式は `inlineBase64` または将来の `contentUri` として渡されます。

完全な通信仕様は
[`protocol/extension-protocol.md`](../protocol/extension-protocol.md) を参照してください。
動作する Python の例は
[`fixtures/extensions/valid-runtime.py`](../fixtures/extensions/valid-runtime.py) にあります。

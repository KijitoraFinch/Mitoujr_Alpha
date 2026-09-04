# 外部 Extension の作成方法

## 実装するもの

外部 Extension は、次の二つで構成します。

- 一つの capability を宣言する JSON manifest
- 標準入力から request を読み、標準出力へ response を返す executable

manifest には executable path、引数、条件分岐、および pipeline を書きません。実行許可と
起動方法は CLI または workspace 外の installed registry snapshot で与えます。

protocol version `"1"` で通常コマンドが実行する role と method は次のとおりです。

| capability type | method | 呼び出し規則 |
|---|---|---|
| `resource-observer` | `monika.observeResource` | exact observer identity ごとに一つ |
| `interpreter` | `monika.interpretObservation`、`monika.resolveRegion` | 固定済み Observation に適用可能な候補を一つだけ選択 |
| `interpreter` | `monika.classifyRegionExtents` | 同じ Observation と Interpreter の部分 Region の比較時 |
| `annotation-extractor` | `monika.extractAnnotations` | 適用可能な候補をすべて実行し、結果を加算 |
| `reference-extractor` | `monika.extractReferences` | 適用可能な候補をすべて実行し、結果を加算 |
| `auditor` | `monika.audit` | installed 候補をすべて実行し、policy 検証後の診断を加算 |
| `deriver` | `monika.derive` | request が指定した exact identity を実行 |

## Manifest

Interpreter manifest の例を示します。

```json
{
  "protocolVersion": "1",
  "capability": {
    "type": "interpreter",
    "name": "example-language",
    "version": "1",
    "acceptedObservationTypes": [
      { "name": "text/x-example", "version": "1" }
    ],
    "applicability": {
      "pathGlobs": ["**/*.example"]
    },
    "selectorSchemas": [
      "https://example.com/schemas/example-selector-v1.json"
    ],
    "resultSchemas": [
      "https://monika.local/schemas/interpretation.schema.json"
    ]
  }
}
```

すべての capability は、次の field を明示します。

- `type`、`name`、`version`: exact capability identity
- `acceptedObservationTypes`: ObservationType の `name` と `version` の組
- `applicability.pathGlobs`: workspace Origin に対する path 制約
- `selectorSchemas`: capability が受理する Extension Selector の schema identity
- `resultSchemas`: 非空の結果 schema identity 集合

Resource Observer では `acceptedObservationTypes` は生成可能な型です。それ以外の role
では受理可能な入力型です。`pathGlobs` が空なら Origin を問わず path 制約はありません。
workspace path を持たない Origin は、非空の `pathGlobs` を満たしません。
配列は集合として比較され、重複要素は不正です。

Extractor の `interpretation` field は任意です。field がない request でも Observation だけで
抽出できる場合は処理を継続できます。ReferenceUse の source は `whole-observation` を使用し、
入力にない concrete Region ID を合成してはいけません。Annotation の未解決 Region は
RegionAddress で表します。

既存の Selector に対する解決結果、抽出規則、または結果 schema の意味を変更する場合は、
既存 identity の動作を上書きせず `version` を更新します。完全な形式は
[`extension-manifest.schema.json`](../schemas/extension-manifest.schema.json) にあります。

## Session の初期化

Monika は executable を shell を介さずに起動し、最初に
`monika.initializeSession` を送ります。

```json
{"jsonrpc":"2.0","id":1,"method":"monika.initializeSession","params":{"protocolVersions":["1"],"maxMessageBytes":16777216,"maxContentBytes":268435456}}
```

Extension は使用する version、manifest と同一の capability、および自分が扱える二つの
上限を返します。

```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1","capability":{"type":"interpreter","name":"example-language","version":"1","acceptedObservationTypes":[{"name":"text/x-example","version":"1"}],"applicability":{"pathGlobs":["**/*.example"]},"selectorSchemas":["https://example.com/schemas/example-selector-v1.json"],"resultSchemas":["https://monika.local/schemas/interpretation.schema.json"]},"maxMessageBytes":16777216,"maxContentBytes":268435456}}
```

以後の session では、host と Extension が提示した値の小さい方を
`maxMessageBytes` と `maxContentBytes` に使用します。静的 manifest と初期化結果の
capability が一致しない場合、Monika は capability method を呼びません。

Python で初期化応答を組み立てる最小部分は次の形です。

```python
request = json.loads(sys.stdin.readline())
if request["method"] != "monika.initializeSession":
    raise ValueError("session is not initialized")
response = {
    "jsonrpc": "2.0",
    "id": request["id"],
    "result": {
        "protocolVersion": "1",
        "capability": CAPABILITY,
        "maxMessageBytes": 16 * 1024 * 1024,
        "maxContentBytes": 256 * 1024 * 1024,
    },
}
print(json.dumps(response, separators=(",", ":")), flush=True)
```

完全に動作する process の例は
[`valid-runtime.py`](../fixtures/extensions/valid-runtime.py) と
[`related-runtime.py`](../fixtures/extensions/related-runtime.py) にあります。

## Observation content の受け渡し

byte-backed Observation を受け取る method request は、次の descriptor を持ちます。

```json
"content": { "kind": "byteStream", "byteLength": 123 }
```

request の直後に `monika.contentChunk` が0回以上、`monika.endContent` が1回届きます。
Extension は request ID、ゼロ起点で連続する offset、Base64 decode 後の byte 数、および
終端長を検査してから response を返します。空の content でも終端 notification は届きます。

構造化 Observation は `representation.kind: "structured"`、schema identity、および
正規化済み JSON value を Observation 自体に持ちます。この場合、request に `content` は
なく、content notification も届きません。byte-backed Observation の `content` を省略したり、
構造化 Observation に `content` を付けたりしてはいけません。

Resource Observer が byte-backed Observation を生成する場合は、response より前に
`monika.outputContentChunk` と `monika.endOutputContent` を送ります。Monika は受信した
byte 列を固定し、response の ContentIdentity と一致することを検査します。構造化
Observation は response 内に正規化済み JSON value を返し、output stream を使いません。

Interpreter、Extractor、Auditor、および Deriver には、Observation content の所在として host
filesystem の絶対 path、再取得用 URI、または host resource token は渡されません。Observation
や RegionAddress が持つ宣言的な Origin は所在情報ではありません。workspace の file を開き直して
Observation content として使用してはいけません。Resource Observer は、宣言的な Extension
Origin と install 時に許可された観測 authority を入力として Resource を観測します。

## 結果の構築

各 capability method は、role 固有の成功値または共通の `failure` の一方を返します。

```json
{
  "failure": {
    "code": "unsupported-observation",
    "message": "observation content is not supported",
    "data": { "format": "example-v2" }
  }
}
```

`failure` は処理済みの意味的失敗です。壊れた params、未実装 method などの protocol
failure には JSON-RPC error response を使います。Monika は Extension の `code` と
任意の `data` を `diagnostics[].extensionFailure` に保持し、空結果や別の capability の
結果へ置き換えません。

Interpreter が返す Region は request の Observation に属し、要求された Selector と
一致しなければなりません。byte-backed Observation の `range` は byte stream に対する
ゼロ起点の半開区間です。構造化 Observation の Region は byte `range` を持たず、型固有の
位置を Selector または structured SourceLocation で表します。

Extractor が返す occurrence は、request の Observation に属する SourceLocation を持ちます。
Extractor request の `interpretation` は任意です。ObservationType に直接適用できる Extractor は、
Interpreter が存在しない場合もこの field を省略した request を処理しなければなりません。
Interpreter と `resolveRegion` が返す部分 Region は exact Interpreter name/version を Region 自体に
含めます。Whole Region では両 field を省略します。Host は manifest から不足 field を補完しません。
Auditor と Deriver は request の `WorkspaceGraphSnapshot` だけを読み、workspace を再走査
しません。Deriver は file を直接変更せず、Core が検証して `monika apply` で適用できる
patch を返します。

全 method の正確な request、result、Failure、および notification は
[`extension-runtime-methods.schema.json`](../schemas/extension-runtime-methods.schema.json)
と [`extension-protocol.md`](../protocol/extension-protocol.md) に従ってください。

## 検証と一時実行

静的 manifest だけを検証する場合は次を実行します。

```sh
monika extension test --manifest extension.json
```

process の起動、初期化、上限交渉、および終了まで検証する場合は executable を指定します。

```sh
monika extension test \
  --manifest extension.json \
  --executable python3 \
  --argument /absolute/path/to/extension.py \
  --launch-path /absolute/path/to/extension.py
```

`--argument` は指定順を保って繰り返せます。`--launch-path` も繰り返せますが、authority の
正規化済み集合であり、重複 path は不正です。script、shared data、または launcher が読む
必要のある file/directory を read-only で sandbox に公開します。成功結果の
`summary.runtimeChecked` は `true` です。
`summary.methodsChecked` は role ごとに検査した method 数です。検査は初期化だけでなく、
manifest が宣言したすべての capability method に型付きの合成入力を送り、成功値または
正しい Failure を decode し、stdin の EOF 後1秒以内に process が status `0` で終了する
ことまで確認します。

開発中の Interpreter は `inspect` または `related` の一時 option で実行できます。

```sh
monika inspect \
  --workspace . \
  --observation docs/example.example \
  --extension-manifest extension.json \
  --extension-executable python3 \
  --extension-argument /absolute/path/to/extension.py \
  --extension-launch-path /absolute/path/to/extension.py
```

一時 option は workspace の設定を書き換えません。選択された ObservationType と canonical
path が manifest の適用条件に一致しなければ、Extension は実行されません。同じ固定済み
Observation に複数の Interpreter が適用可能な場合、暗黙の優先順位を設けず dispatch
failure にします。

## Installed registry

複数 role、cross-interpreter resolve、および Extension Origin の観測には、workspace 外の
不変な registry snapshot を `--extension-registry` で渡します。

```json
{
  "schemaVersion": "2",
  "extensions": [
    {
      "manifest": {
        "protocolVersion": "1",
        "capability": {
          "type": "interpreter",
          "name": "example-language",
          "version": "1",
          "acceptedObservationTypes": [
            { "name": "text/x-example", "version": "1" }
          ],
          "applicability": { "pathGlobs": ["**/*.example"] },
          "selectorSchemas": [
            "https://example.com/schemas/example-selector-v1.json"
          ],
          "resultSchemas": [
            "https://monika.local/schemas/interpretation.schema.json"
          ]
        }
      },
      "executable": "/absolute/path/to/python3",
      "arguments": ["/absolute/path/to/extension.py"],
      "authority": {
        "kind": "sandboxed",
        "launchPaths": ["/absolute/path/to/extension.py"]
      }
    }
  ]
}
```

`executable` は絶対 path です。同じ capability type/name/version の重複と built-in
identity との衝突は、dispatch 前に拒否されます。Reference target が Extension Selector
を使う場合、その schema identity は target Interpreter の `selectorSchemas` に含まれ、
target は exact Interpreter name/version を記録しなければなりません。

`launchPaths` には、Extension 自体だけでなく、実行に必要な依存物も明示します。たとえば、
利用者が管理する prefix にインストールされた Python を `executable` に指定し、標準
library が executable とは別の directory にある場合は、その Python runtime root も
`launchPaths` に含めます。Monika は executable の親 directory から依存物への権限を推測
しません。信頼済みの system installation root にある runtime だけは、起動に必要な
system resource として host が限定的に解決します。

Resource Observer の entry では、通常の `sandboxed` authority の代わりに、観測 authority
を明示します。

```json
{
  "kind": "resource-observer",
  "originClass": "extension",
  "launchPaths": ["/absolute/path/to/observer.py"],
  "resourceReadPaths": ["/absolute/path/to/observed-resource"],
  "network": false
}
```

`resourceReadPaths` は read-only です。network access は既定で拒否され、`network: true` の
ときだけ許可されます。この authority は Resource Observer にだけ使用でき、ほかの role
では registry の decode 後、process 起動前に拒否されます。一時的な Resource Observer の
適合性検査では `--resource-read-path` と `--allow-network` が同じ意味を持ちます。

macOS は OS 標準の `sandbox-exec`、Linux は bubblewrap (`bwrap`) を必要とします。sandbox
機構がない場合は安全でない通常起動へ切り替えません。Windows では現在、静的 manifest
検査は利用できますが、Extension process の実行は `sandbox-setup-failed` になります。

## 失敗時の確認

Extension を開始した後の失敗は、正常な JSON result channel に構造化されます。
`CommandResult` では `diagnostics[].extensionFailure`、`RelatedResult` では同じ形の
diagnostic を確認します。代表的な code は次のとおりです。

| code | 確認する箇所 |
|---|---|
| `sandbox-setup-failed` | 対応 OS、`sandbox-exec` / `bwrap`、authority path |
| `invalid-authority` | capability role と authority variant の対応 |
| `spawn-failed` | executable path、実行権限、`PATH` |
| `timeout` | stdin の読み取り、stdout の flush、処理時間 |
| `request-too-large` / `response-too-large` | 交渉後の `maxMessageBytes` |
| `content-too-large` | 交渉後の `maxContentBytes` |
| `invalid-response` | JSON、未知 field、ID、stream offset、終端、結果 invariant |
| `remote-error` | Extension が返した JSON-RPC error |
| `process-exit` | EOF 後の終了 status、signal |
| `shutdown-timeout` | EOF 後も終了しない処理 |
| `manifest-mismatch` | process 内の capability と静的 manifest |

静的 manifest 自体の不正は Extension operation の失敗ではないため、`invalid-input` の
usage error となり `extensionFailure` を作りません。

## 実装時の確認事項

- stdout には一行の JSON protocol message 以外を書かず、log は stderr へ書きます。
- 各 response の ID は request と同じ値にし、書いた直後に stdout を flush します。
- object の field name を重複させず、未知 field と `null` による省略を使いません。
- 小数を送らず、整数を JavaScript safe integer の範囲内にします。
- `maxMessageBytes`、`maxContentBytes`、連続 offset、および stream 終端を検査します。
- `result` と `error` の一方だけを返します。
- session をまたぐ隠れた状態に結果の正しさを依存させません。
- workspace を直接変更しません。必要な read-only file は launch binding または Resource
  Observer authority に明示し、親 process の環境変数や current working directory に依存しません。
- scratch は session 固有であり、永続状態には使用しません。各 file の上限は16 MiB です。

# Extension protocol

## 適用範囲

protocol version `"1"` は、静的 manifest、外部プロセスを起動して
`monika.initializeSession` を呼ぶ通信方式、interpreter extension の
`monika.interpretObservation`、および
`monika.resolveRegion` を定めます。annotation の抽出、audit、および patch の生成に
使う method は、まだこの protocol version の実行可能な契約に含めません。

この文書で extension process とは、Monika が直接起動し、標準入力と標準出力で
JSON-RPC message を交換する外部プロセスを指します。一つの message は、一つの
JSON-RPC request または response です。一回の session は、そのプロセスを起動して
から終了を確認するまでです。

## 静的 manifest

manifest は、`protocolVersion` と一つの `capability` を持つ閉じた JSON object
です。形式は [`extension-manifest.schema.json`](../schemas/extension-manifest.schema.json)
で定めます。manifest には executable path、引数、条件分岐、pipeline などの
実行手順を書きません。

## プロセスの起動

現在の参照実装では、次の CLI で executable と引数を指定します。

```sh
monika extension test \
  --manifest extension.json \
  --executable python3 \
  --argument extension.py
```

`--argument` は指定順に何度でも使用できます。Monika は shell を介さず、
executable と引数の配列を operating system の process API へ渡します。環境変数と
current working directory は Monika process から継承します。extension は current
working directory の特定の値に依存してはいけません。

manifest と executable の永続的な登録方法は、この protocol version では定めません。
通常コマンドで一時的に使用する extension は、CLI の `--extension-manifest`、
`--extension-executable`、および `--extension-argument` で指定します。

`monika resolve` の一時 interpreter session では、manifest 照合後に source observation の
`monika.interpretObservation` を一回呼び、その interpretation から選択した reference の
target に対して
`monika.resolveRegion` を一回呼びます。この二つは同じ process session で順に実行します。

## Message の区切り

通信には JSON-RPC 2.0 を使用します。標準入力と標準出力は UTF-8 を使用し、一つの
JSON object を一行に書きます。各 message の末尾には LF を一つ書きます。JSON string
内の改行は JSON の escape sequence として書くため、物理的な改行にはなりません。

protocol version 1 では、Monika が request を一つ送り、対応する response を受け取って
から次の request を送ります。notification、batch request、および extension process
から Monika への request は使用しません。request ID は1から始まる正の整数です。

標準出力には protocol message 以外を書いてはいけません。診断用の log は標準エラー
出力へ書きます。

## JSON の制約

request と response には、次の制約を適用します。

- object の field name は重複できません。
- string と field name は正しい UTF-8 でなければなりません。
- number は `-9007199254740991` 以上 `9007199254740991` 以下の整数に限ります。
- 小数、`NaN`、および無限大は使用できません。
- array と object の入れ子は、最上位の値から128段までです。
- 定義されていない field は使用できません。
- optional field を使用しない場合は省略します。`null` で代用しません。

## `monika.initializeSession`

Monika は process を起動した後、最初に次の request を送ります。
process の起動からこの request が成功するまでは未初期化 session です。未初期化
session ではほかの method を呼びません。成功後は初期化済み session となり、同じ
session で `monika.initializeSession` を再度呼びません。

```json
{"jsonrpc":"2.0","id":1,"method":"monika.initializeSession","params":{"protocolVersions":["1"],"maxMessageBytes":16777216}}
```

`protocolVersions` は Monika が使用できる version です。request の `maxMessageBytes` は、
Monika が送受信できる一つの message の最大 byte 数です。末尾の LF は数えません。

成功した extension は、使用する protocol version と capability を返します。

```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1","capability":{"type":"interpreter","name":"custom-markdown","version":"1"},"maxMessageBytes":16777216}}
```

result の `maxMessageBytes` は extension process が送受信できる最大 byte 数です。
`monika.initializeSession` の完了後は、request と result に書かれた二つの上限のうち小さい値を
使用します。`monika.initializeSession` 自体の response には、request で Monika が示した上限を
使用します。

result の `protocolVersion` と `capability` は、CLI で指定した静的 manifest と
一致しなければなりません。
`mediaTypes` と `pathGlobs` の順序は比較に影響しません。それ以外の field は、値と
有無が一致しなければなりません。

### applicability の評価

`pathGlobs` は workspace-relative path 全体に対して case-sensitive に評価します。
この規則は operating system に依存しません。segment 内の `*` はその segment 内の
0 byte 以上に一致し、segment 全体が `**` の場合は0個以上の path segment に一致します。
先頭または末尾の `/`、空 segment、`.`、`..`、segment 内の `**`、および `?`、`[]`、
backslash は不正です。複数の glob は OR です。

既知の suffix は `.md` / `.markdown` を `text/markdown`、`.yaml` / `.yml` を
`application/yaml`、`.jsonl` / `.ndjson` を `application/x-ndjson` として判定します。
`mediaTypes` と `pathGlobs` が両方ある場合、両方に一致しなければ適用しません。suffix
から media type を判定できない path は、一つの `mediaTypes` と一致する `pathGlobs`
がある場合に限り、その対応を明示的な file association として使用します。候補となる
media type が複数ある場合は曖昧な指定として失敗します。`appliesTo` 自体がない
capability は全 path に適用可能です。

これらの規則による file association は、workspace の Observation Provider が
Observation を構築する段階で評価します。Interpreter の候補選択は、その後で固定済みの
ObservationType と path を `appliesTo` に照合するだけです。候補選択が ObservationType を
返したり、既存の Observation を別の型で作り直したりすることはありません。

workspace graph の一回の構築試行では、適用対象を canonical observation ID 順に
`monika.interpretObservation` へ渡し、一つの checked session を再利用します。workspace の変更により
試行を破棄する場合、retry は新しい process と checked session で開始します。

明示された extension が適用不能な observation へ `monika.interpretObservation` を送ってはいけません。
また、`related` のように interpreter 候補を選択する操作で、同じ observation に built-in
interpreter と extension interpreter の両方が適用される場合、暗黙の優先順位を設けず
dispatch failure にします。`inspect` と `resolve` の extension option は interpreter 自体を
明示的に選択していますが、その場合も applicability に一致しなければ実行しません。

request を処理できない場合は JSON-RPC error response を返します。

```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"method not found"}}
```

成功 response の `id` は request と一致しなければなりません。error response でも
通常は同じ ID を返します。request を JSON-RPC request として解釈できず、ID を取得
できなかった場合に限り、error response の `id` を `null` にできます。`result` と
`error` は同時に指定できません。正確な構造は
[`extension-runtime-initialize-session.schema.json`](../schemas/extension-runtime-initialize-session.schema.json)
で定めます。

extension process は、JSON-RPC 2.0 が定める `-32700`、`-32600`、`-32601`、`-32602`、
および `-32603` を、それぞれ parse error、invalid request、method not found、invalid
params、および internal error に使用します。提示された protocol version を一つも使用
できない場合は、code `-32001` と message `unsupported protocol version` を返します。

## 内容転送

Monika は内容を「text document」としてではなく、`ContentIdentity` を持つ read-only byte
resource として extension に渡します。この方針は Git、Nix、および OCI image layer の
ような content-addressed object の考え方に合わせたものです。text は重要な表現の一つ
ですが、binary、schema 付き JSON、PDF、Parquet、および Web API response と同列です。

protocol version 1 の `content` は、次の tagged union です。

- `{ "kind": "inlineText", "text": <string> }`
- `{ "kind": "inlineBase64", "base64": <base64> }`
- `{ "kind": "contentUri", "uri": <uri>, "contentIdentity": <ContentIdentity>, "expiresWith": "session" }`

参照実装が現在送るのは `inlineText` と `inlineBase64` です。`contentUri` は、大きな
content を一つの JSON message に複製しないための予約済み形です。`contentUri` が指す
resource は read-only であり、少なくとも session 終了までは、同じ `contentIdentity`
の byte 列を返さなければなりません。extension は `uri` の文字列構文に意味を仮定せず、
Monika が定める scheme だけを使用します。

`inlineText` は UTF-8 text を表します。`inlineBase64` は text か binary かを問わない
byte 列を表します。どちらの場合も、正準の content identity は `observation.contentIdentity`
にあります。extension は inline payload から独自に identity を再定義してはいけません。

## Range の単位

protocol 内のすべての `range` は、対象 observation の正確な content byte 列に対する
ゼロ起点の半開区間 `[start, end)` です。`start` は先頭 byte を含み、`end` は末尾 byte
を含みません。`inlineText` の場合も、Unicode code point、grapheme cluster、UTF-16
code unit ではなく、UTF-8 へ encode した byte 列の offset を使用します。
`inlineBase64` の場合は decode 後の byte 列を使用します。したがって、全体 range の
`end` は `observation.contentIdentity.size` と一致します。

## `monika.interpretObservation`

`monika.interpretObservation` は、既に固定された一つの observation とその content を
Interpreter に渡し、interpretation を返します。Observation を作る操作ではありません。
Monika は `monika.initializeSession` の manifest 照合に成功した後だけ、この method を
呼びます。

request の `params` は次の field を持ちます。

- `observation`: CommandResult と同じ observation object
- `content`: 前節の content tagged union

成功時の response result は、`interpretation` または `failure` の一方だけを持ちます。

```json
{
  "interpretation": {
    "regions": [],
    "references": [],
    "annotations": []
  }
}
```

`interpretation` 内の `regions`、`references`、および `annotations` は CommandResult と
同じ正規形を使用します。interpreter extension が返す非 whole region では、
`interpreter` と `interpreterVersion` を省略できます。その場合、Monika は照合済み
manifest の capability name と version を補います。明示する場合は manifest と
一致しなければなりません。

Interpretation は新しい Observation を含みません。新しい Observation を生成する責務は
Observation Provider にあり、Interpreter は request で受け取った Observation を変更、
再分類、または置換してはいけません。返すすべての Region、Reference、および Annotation
は request の Observation に属さなければなりません。

対象を解釈できないなど、protocol 自体は成功したが interpretation を返せない場合は
`failure` を返します。

```json
{
  "failure": {
    "code": "unsupported-observation",
    "message": "observation content is not supported"
  }
}
```

JSON が壊れている、method がない、params の型が不正であるなどの protocol-level failure
は、`result.failure` ではなく JSON-RPC error response で返します。

## `monika.resolveRegion`

`monika.resolveRegion` は、一つの observation、content、および selector から、対応する
region を返します。request の `params` は `observation`、`content`、および `selector` を
持ちます。`selector` は CommandResult と同じ selector object です。

成功時の response result は、`region` または `failure` の一方だけを持ちます。
`region` は CommandResult と同じ region object です。`failure` は
`monika.interpretObservation` と
同じ形です。selector が extension の schema に合わない場合や、現在の content で
解決できない場合は `failure` を返します。

Monika は `region` を受理する前に、region の observation ID と observation identity が request
の observation に一致すること、selector が request と等しいこと、interpreter name/version
が照合済み manifest と一致すること、および range が target content の byte length 内に
あることを検査します。extension は類似する selector や古い observation の region を代替
結果として返してはいけません。

`monika.interpretObservation` と `monika.resolveRegion` の正確な構造は
[`extension-runtime-methods.schema.json`](../schemas/extension-runtime-methods.schema.json)
で定めます。

## 上限時間と終了

参照実装の既定値は次のとおりです。

| 対象 | 既定値 |
|---|---:|
| 一つの message | 16 MiB |
| request の書き込み開始から response の読了まで | 30秒 |
| 標準入力を閉じてから process が終了するまで | 1秒 |

Monika は session の最後に extension process の標準入力を閉じます。extension process は
EOF を受け取ったら処理を終え、終了 status `0` で終了しなければなりません。上限時間
までに終了しない場合、Monika は process を強制終了して回収します。

不正な response、上限超過、timeout、途中の EOF、書き込み失敗、および終了 status
`0` 以外は session の失敗です。失敗した session の process は再利用しません。

## 権限

この通信方式は extension process を sandbox 内で実行しません。process は Monika と
同じ operating system user の権限を継承します。「extension は workspace を直接変更
しない」という規則は protocol 上の要件ですが、現在の参照実装は operating system
の機能を使って書き込みを禁止していません。信頼できない executable を起動しては
いけません。

# Extension protocol

## 適用範囲

protocol version `"1"` は、静的 manifest、外部プロセスを起動して
`monika.initializeSession` を呼ぶ通信方式、interpreter extension の
`monika.interpretObservation`、および
`monika.resolveRegion`、`monika.classifyRegionExtents` を定めます。annotation の抽出、audit、および patch の生成に
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

protocol version 1 の外部 manifest で指定できる capability は `interpreter` だけです。
ほかの capability 種別は core の分類として存在しますが、対応する runtime method の
入力、結果、および失敗の契約が定義されるまでは、外部 manifest として受理しません。
同様に、`capability.schemas` で指定できるのは、`resolveRegion` が実際に参照する
`selector` だけです。runtime method に渡す手段がない `annotation` と `options` は
version 1 の外部 manifest では受理しません。

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

install 済みの実行許可は、workspace 外の
[`extension-registry.schema.json`](../schemas/extension-registry.schema.json) に記録します。
registry entry は manifest と、host が起動する絶対 executable path、引数の配列を持ちます。
これは workspace の意味宣言ではなく、host installation state の snapshot です。同じ
capability type/name/version は一つの snapshot に重複できません。

通常コマンドで一時的に使用する extension は、CLI の `--extension-manifest`、
`--extension-executable`、および `--extension-argument` で指定できます。複数
Interpreter と exact name/version dispatch を使用する場合は `--extension-registry` を
指定します。

## Message の区切り

通信には JSON-RPC 2.0 を使用します。標準入力と標準出力は UTF-8 を使用し、一つの
JSON object を一行に書きます。各 message の末尾には LF を一つ書きます。JSON string
内の改行は JSON の escape sequence として書くため、物理的な改行にはなりません。

protocol version 1 では、Monika が capability request を一つ送り、内容を伴う request
では直後に `monika.contentChunk` を0回以上、`monika.endContent` を1回 notification として
送ります。Extension は終端 notification まで受信してから response を返します。その
response を受け取るまで、Monika は次の capability request を送りません。batch request
および extension process から Monika への request は使用しません。request ID は1から
始まる正の整数です。

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

これらの規則による file association は、workspace の Resource Observer が
Observation を構築する段階で評価します。Interpreter の候補選択は、その後で固定済みの
ObservationType と path を `appliesTo` に照合するだけです。候補選択が ObservationType を
返したり、既存の Observation を別の型で作り直したりすることはありません。

workspace graph の一回の構築試行では、適用対象を canonical observation ID 順に処理し、
各 Observation を capability ごとの dispatcher で一意な Interpreter へ割り当てます。
installed Extension は Observation ごとに独立した checked session で実行します。正しさを
process 内の session 状態に依存させません。workspace の変更により試行を破棄する場合、
retry は新しい process と checked session で開始します。

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

Monika は内容を「text document」や filesystem path としてではなく、固定済み
Observation に属する byte stream として extension に渡します。request の `content` は
`{ "kind": "byteStream", "byteLength": <integer> }` です。これは所在を示す handle では
ありません。

Monika は request の直後に、同じ request ID、ゼロ起点の連続 offset、および Base64 化した
byte 列を持つ notification を送ります。

```json
{"jsonrpc":"2.0","method":"monika.contentChunk","params":{"requestId":2,"offset":0,"base64":"..."}}
{"jsonrpc":"2.0","method":"monika.endContent","params":{"requestId":2,"byteLength":123}}
```

`contentChunk` の decode 後の長さを順に加えた値は、次の offset と終端の `byteLength` に
一致しなければなりません。終端値は request の `content.byteLength` および
`observation.contentIdentity.size` と一致します。空内容でも `endContent` は送ります。

Extension へ path、URI、または host resource token は渡しません。内容が大きい場合も
Extension が workspace を開き直すことはなく、同じ stream 契約を使います。random access
が必要な Extension は、受け取った byte 列を自ら管理する一時領域へ保存できます。その
場合も入力の正準 identity は `observation.contentIdentity` です。

## Range の単位

protocol 内のすべての `range` は、対象 observation の正確な content byte 列に対する
ゼロ起点の半開区間 `[start, end)` です。`start` は先頭 byte を含み、`end` は末尾 byte
を含みません。text の場合も、Unicode code point、grapheme cluster、UTF-16 code unit
ではなく、stream で受信した byte 列の offset を使用します。したがって、全体 range の
`end` は `observation.contentIdentity.size` と一致します。

## `monika.interpretObservation`

`monika.interpretObservation` は、既に固定された一つの observation とその content を
Interpreter に渡し、interpretation を返します。Observation を作る操作ではありません。
Monika は `monika.initializeSession` の manifest 照合に成功した後だけ、この method を
呼びます。

request の `params` は次の field を持ちます。

- `observation`: CommandResult と同じ observation object
- `content`: 前節の byte stream descriptor

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

Interpretation は新しい Observation を含みません。Resource を観測して新しい
Observation を生成する責務は Resource Observer にあり、Interpreter は request で
受け取った Observation を変更、再分類、または置換してはいけません。返すすべての
Region、Reference、および Annotation は request の Observation に属さなければなりません。

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

`failure` は、必須の `code` と `message`、および任意の `data` を持ちます。`data` は
本 protocol の JSON 制約を満たす任意の値です。Monika は、extension が返した
`code` と `data` を捨てず、`CommandResult` の diagnostic にある
`extensionFailure` へ正規化して保持します。`message` は diagnostic の message として
保持します。別の解釈結果を暗黙に選ぶ fallback は行いません。

JSON が壊れている、method がない、params の型が不正であるなどの protocol-level failure
は、`result.failure` ではなく JSON-RPC error response で返します。Monika が受信した
JSON-RPC error の数値 code と任意の `data` も、`extensionFailure.data` の
`jsonRpcCode` と `data` に保持します。

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

## `monika.classifyRegionExtents`

`monika.classifyRegionExtents` は、同じ固定 Observation に属し、同じ Interpreter が生成した
二つの部分 Region について、左から右を見た領域関係を返します。request は
`observation`、`content`、`left`、`right` を持ちます。成功 result は次の五値の
`relation`、または `failure` の一方だけを持ちます。

- `equal`
- `contains`
- `contained-by`
- `overlaps`
- `disjoint`

この五値は比較可能な一組について排他的かつ網羅的です。引数を逆にすると `contains` と
`contained-by` が入れ替わり、ほかの三値は変わりません。`equal` は同値関係、strict な
`contains` と `contained-by` は推移的で非反射的です。`overlaps` と `disjoint` は対称です。
Region ID、selector の構造、または任意に付与された byte range の一致を、Extension の
領域意味論に代用してはいけません。

whole Observation と部分 Region の関係は core が決定し、この method を呼びません。異なる
Observation または異なる Interpreter の部分 Region は比較不能として明示的に失敗します。
Extension の失敗を `disjoint` などの関係値へ変換しません。

`monika.interpretObservation`、`monika.resolveRegion`、および
`monika.classifyRegionExtents` の正確な構造は
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

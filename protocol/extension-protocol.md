# Extension protocol

## 適用範囲

protocol version `"1"` は、静的 manifest、外部プロセスを起動して
`monika.initializeSession` を呼ぶ通信方式と、次の capability method を定めます。

- Resource Observer: `monika.observeResource`
- Interpreter: `monika.interpretObservation` と `monika.resolveRegion`
- Region extent: `monika.classifyRegionExtents`
- Annotation Extractor: `monika.extractAnnotations`
- Reference Extractor: `monika.extractReferences`
- Auditor: `monika.audit`
- Deriver: `monika.derive`

この文書で extension process とは、Monika が直接起動し、標準入力と標準出力で
JSON-RPC message を交換する外部プロセスを指します。一つの message は、一つの
JSON-RPC request または response です。一回の session は、そのプロセスを起動して
から終了を確認するまでです。

## 静的 manifest

manifest は、`protocolVersion` と一つの `capability` を持つ閉じた JSON object
です。形式は [`extension-manifest.schema.json`](../schemas/extension-manifest.schema.json)
で定めます。manifest には executable path、引数、条件分岐、pipeline などの
実行手順を書きません。

manifest の capability type は core が認識する閉じた種類から選びます。各 capability は
`type`、`name`、`version`、`acceptedObservationTypes`、
`applicability.pathGlobs`、`selectorSchemas`、および非空の `resultSchemas` を必ず
宣言します。ObservationType は `name` と `version` の組で完全一致させます。
Resource Observer の `acceptedObservationTypes` は生成可能な型を表し、ほかの role では
受理できる入力型を表します。

## プロセスの起動

現在の参照実装では、次の CLI で executable と引数を指定します。

```sh
monika extension test \
  --manifest extension.json \
  --executable python3 \
  --argument /absolute/path/to/extension.py \
  --launch-path /absolute/path/to/extension.py
```

`--argument` は指定順に何度でも使用できます。Monika は shell を介さず、
executable と引数の配列を operating system の process API へ渡します。親 process の
環境変数と current working directory は継承しません。`HOME`、一時領域、`PATH`、locale、
timezone だけを固定した環境を渡し、current working directory は session 固有の scratch
領域にします。引数として渡す script や data file は、`--launch-path` でも読み取りを
許可しなければなりません。

install 済みの実行許可は、workspace 外の
[`extension-registry.schema.json`](../schemas/extension-registry.schema.json) に記録します。
registry entry は manifest と、host が起動する絶対 executable path、引数の配列、および
`authority` を持ちます。
これは workspace の意味宣言ではなく、host installation state の snapshot です。同じ
capability type/name/version は一つの snapshot に重複できません。

通常コマンドで一時的に使用する extension は、CLI の `--extension-manifest`、
`--extension-executable`、および `--extension-argument` で指定できます。
複数 role の exact dispatch と加算的な Extractor／Auditor 実行を使用する場合は
`--extension-registry` を指定します。

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
{"jsonrpc":"2.0","id":1,"method":"monika.initializeSession","params":{"protocolVersions":["1"],"maxMessageBytes":16777216,"maxContentBytes":268435456}}
```

`protocolVersions` は Monika が使用できる version です。request の `maxMessageBytes` は、
Monika が送受信できる一つの message の最大 byte 数です。`maxContentBytes` は、
一つの Observation content stream の最大 byte 数です。末尾の LF は数えません。

成功した extension は、使用する protocol version と capability を返します。

```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1","capability":{"type":"interpreter","name":"custom-markdown","version":"1","acceptedObservationTypes":[{"name":"text/markdown","version":"1"}],"applicability":{"pathGlobs":["docs/*.md"]},"selectorSchemas":[],"resultSchemas":["https://monika.local/schemas/interpretation.schema.json"]},"maxMessageBytes":16777216,"maxContentBytes":268435456}}
```

result の `maxMessageBytes` と `maxContentBytes` は extension process が扱える上限です。
`monika.initializeSession` の完了後は、それぞれ request と result に書かれた二つの
上限のうち小さい値を使用します。`monika.initializeSession` 自体の response には、request
で Monika が示した message 上限を使用します。

result の `protocolVersion` と `capability` は、CLI で指定した静的 manifest と
一致しなければなりません。
各配列の意味値は正規順序で比較します。それ以外の field も含め、静的 manifest と
初期化応答は同じ capability 値でなければなりません。

### applicability の評価

`pathGlobs` は workspace-relative path 全体に対して case-sensitive に評価します。
この規則は operating system に依存しません。segment 内の `*` はその segment 内の
0 byte 以上に一致し、segment 全体が `**` の場合は0個以上の path segment に一致します。
先頭または末尾の `/`、空 segment、`.`、`..`、segment 内の `**`、および `?`、`[]`、
backslash は不正です。複数の glob は OR です。

workspace の Resource Observer は、built-in suffix 規則と registry の明示的な
`acceptedObservationTypes`／`pathGlobs` の対応から ObservationType を一意に決定します。
一つの path glob に複数の ObservationType 候補が対応する場合は、曖昧な file association
として失敗します。

後続 capability の候補選択は、固定済み ObservationType を
`acceptedObservationTypes` に完全一致させます。workspace Origin の場合は canonical path
も `applicability.pathGlobs` に一致させます。空の `pathGlobs` は追加の path 制約がないことを
表します。workspace path を持たない Origin は、非空の `pathGlobs` を満たしません。
候補選択が ObservationType を返したり、既存の Observation を別の型で作り直したりすることは
ありません。

workspace graph の一回の構築試行では、適用対象を canonical observation ID 順に処理し、
各 Observation を capability ごとの dispatcher で一意な Interpreter へ割り当てます。
Interpreter は候補がちょうど一つの場合だけ実行します。Annotation Extractor と Reference
Extractor は同じ Observation に適用可能な候補をすべて canonical capability identity 順に
実行し、結果を型別に加算します。Auditor は installed 候補をすべて実行し、Deriver は
operation が明示する exact identity を実行します。installed Extension は Observation と capability の組ごとに独立した checked
session で実行します。正しさを process 内の session 状態に依存させません。workspace の
変更により試行を破棄する場合、retry は新しい process と checked session で開始します。

明示された extension が適用不能な Observation へ capability method を送ってはいけません。
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
Observation に属する byte stream として extension に渡します。byte-backed Observation の
request にある `content` は
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

構造化 Observation は `representation.kind: "structured"`、schema identity、および正規化済み
JSON value を Observation object 自体に持ち、`content` field と content notification を
使用しません。byte-backed Observation で `content` を省略すること、または構造化 Observation
に `content` を付けることは protocol error です。

Resource Observer が byte-backed Observation を返す場合は、response より前に逆方向の
`monika.outputContentChunk` と `monika.endOutputContent` notification を送ります。request ID、
offset、Base64、および byteLength の規則は host-to-extension stream と同じです。Monika は
終端までの byte 列を host-owned storage に固定し、response の `contentIdentity` と一致する
ことを検査します。終端のない stream、終端後の chunk、不連続 offset、上限超過、および
response より前に終端しない stream は失敗です。

Interpreter、Extractor、Auditor、および Deriver への Observation content の所在として、host
filesystem の絶対 path、再取得用 URI、または host resource token は渡しません。Observation や
RegionAddress が意味値として持つ宣言的な Origin は、この所在情報とは区別します。内容が大きい場合も Extension が workspace を
開き直すことはなく、同じ stream 契約を使います。random access が必要な Extension は、
受け取った byte 列を自ら管理する一時領域へ保存できます。その場合も入力の正準 identity は
`observation.contentIdentity` です。一つの stream は初期化時に交渉した `maxContentBytes` を
超えてはいけません。Resource Observer はこの content transfer の入力側ではなく、宣言的な
Extension Origin と install 時に付与された観測 authority を入力として受け取ります。

## Range の単位

protocol 内のすべての `range` は、対象 observation の正確な content byte 列に対する
ゼロ起点の半開区間 `[start, end)` です。`start` は先頭 byte を含み、`end` は末尾 byte
を含みません。text の場合も、Unicode code point、grapheme cluster、UTF-16 code unit
ではなく、stream で受信した byte 列の offset を使用します。したがって、全体 range の
`end` は `observation.contentIdentity.size` と一致します。
構造化 Observation の Region は byte `range` を持ちません。型固有の位置は Selector または
`SourceLocation.Structured` で表します。

## `monika.interpretObservation`

`monika.interpretObservation` は、既に固定された一つの Observation を Interpreter に渡し、
Interpretation を返します。Observation を作る操作ではありません。
Monika は `monika.initializeSession` の manifest 照合に成功した後だけ、この method を
呼びます。

request の `params` は次の field を持ちます。

- `observation`: CommandResult と同じ observation object
- `content`: byte-backed Observation の場合だけ必要な byte stream descriptor

成功時の response result は、`interpretation` または `failure` の一方だけを持ちます。

```json
{
  "interpretation": {
    "interpreter": {"name":"custom-markdown","version":"1"},
    "observation": "obs-example",
    "regions": []
  }
}
```

`interpretation.interpreter` は照合済み manifest の capability identity と一致し、
`interpretation.observation` は request の Observation ID と一致しなければなりません。
`regions` は CommandResult と同じ正規形を使用します。Interpreter extension が返す
非 whole region は、照合済み manifest と一致する exact `interpreter` と
`interpreterVersion` を明示します。Whole Region は両 field を持ちません。Monika は
欠落した identity を manifest から補いません。

Interpretation は新しい Observation を含みません。Resource を観測して新しい
Observation を生成する責務は Resource Observer にあり、Interpreter は request で
受け取った Observation を変更、再分類、または置換してはいけません。返すすべての
Region は request の Observation に属さなければなりません。Reference と Annotation は
Interpretation の field ではなく、それぞれ独立した Extractor の結果です。

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

## `monika.observeResource`

`monika.observeResource` は Resource Observer が所有する `ExtensionOrigin` を一回観測します。
request の `params.origin` は checked session の Resource Observer identity と完全一致する
`observer` と、正規化済み `locator` を持ちます。成功 result は `observation` または
`failure` の一方だけを持ちます。

返す Observation の Origin は request と等しく、ObservationType は manifest の
`acceptedObservationTypes` に含まれなければなりません。構造化値は response 内に返します。
byte-backed 値は response より前の output content stream と、response の
`contentIdentity` に分けて返します。Core は完全な byte 列、ContentIdentity、
ObservationIdentity、および Origin の対応を検査してから固定済み Observation を受理します。

## `monika.extractAnnotations`

`monika.extractAnnotations` は、固定済み Observation、存在する場合は同じ Observation の
検証済み Interpretation、および必要な場合の content stream を Annotation Extractor に渡します。
成功 result は `extraction.occurrences` または `failure` の一方だけを持ちます。
各 `AnnotationOccurrence` は request の Observation に属する `SourceLocation` を持ちます。
適用可能なすべての Annotation Extractor を独立した checked session で実行し、成功結果を
加算します。失敗を空の extraction に置き換えません。

## `monika.extractReferences`

`monika.extractReferences` は、固定済み Observation、その content、および存在する場合は同じ
Observation に対する検証済み Interpretation を Reference Extractor に渡します。Reference Extractor は
Observation を作成または置換せず、Reference の定義と use occurrence を返します。

request の `params` は次の field を持ちます。

- `observation`: CommandResult と同じ observation object
- `interpretation`: 存在する場合だけ、`monika.interpretObservation` で検証済みの Interpretation
- `content`: byte-backed Observation の場合だけ必要な byte stream descriptor

成功時の response result は、`extraction` または `failure` の一方だけを持ちます。

Interpreter の候補がないことは、Observation 自体を入力にできる Extractor を無効にしません。
Core は `interpretation` を省略して適用可能な Extractor を実行し、Interpreter の unsupported
coverage と Extractor の結果を別々に保持します。Extension は省略を `null` として要求しては
いけません。

Extractor が concrete な Region ID を返す場合、その Region は request の Interpretation に
含まれるか、Core が入力 Observation に対して公開した Region でなければなりません。
`interpretation` がない Reference Extractor は、source を `whole-observation` とするか、
concrete Region ID を必要としない結果を返します。Annotation の unresolved endpoint は
RegionAddress で表します。利用できない Region ID を含む extraction は、全体を
`invalid-result` として棄却し、一部だけを graph に追加しません。

```json
{
  "extraction": {
    "definitions": [],
    "uses": []
  }
}
```

`definitions` と `uses` は同じ request の Observation に属さなければなりません。
Monika は適用可能な Reference Extractor をすべて独立した checked session で実行し、
成功した結果を加算します。一つの Extractor の失敗を、別の Extractor の成功または空の
結果へ置き換えません。`failure` と JSON-RPC error の扱いは
`monika.interpretObservation` と同じです。

## `monika.resolveRegion`

`monika.resolveRegion` は、一つの Observation と Selector から、対応する Region を返します。
request の `params` は `observation` と `selector`、byte-backed Observation の場合だけ
`content` を持ちます。`selector` は CommandResult と同じ Selector object です。

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
`observation`、`left`、`right`、および byte-backed Observation の場合だけ `content` を
持ちます。成功 result は次の五値の
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

## `monika.audit`

`monika.audit` は一つの固定済み `WorkspaceGraphSnapshot` と宣言的な `AuditPolicy` を
Auditor に渡します。成功 result は `diagnostics` または `failure` の一方だけを持ちます。
返す Diagnostic の effective severity は requested policy と一致しなければなりません。
`sidecarOnly: "allow"` の場合は `sidecar-only` Diagnostic を返してはいけません。Core は
有効なすべての Auditor の結果を code と location の正規順序で加算します。Auditor は
workspace を再走査せず、request の snapshot だけを監査します。

## `monika.derive`

`monika.derive` は一つの固定済み `WorkspaceGraphSnapshot` と宣言的な `DeriveRequest` を
Deriver に渡します。request は `AnnotationOccurrence` または
`ReferenceDefinitionOccurrence` のいずれか一つを閉じた直和型の source occurrence として持ち、
target Origin、target encoding、および正規化済み policy を持ちます。Origin 全体や入力順から
source occurrence を暗黙に選択しません。成功 result は `patches` または `failure` の一方だけを
持ちます。patch ID は結果内で一意で、すべての patch は Core の通常の検証と apply 境界を
通ります。Deriver は workspace を再走査せず、file を直接書き換えません。

すべての capability method と content notification の正確な構造は
[`extension-runtime-methods.schema.json`](../schemas/extension-runtime-methods.schema.json)
で定めます。

## 上限時間と終了

参照実装の既定値は次のとおりです。

| 対象 | 既定値 |
|---|---:|
| 一つの message | 16 MiB |
| 一つの Observation content stream | 256 MiB |
| request の書き込み開始から response の読了まで | 30秒 |
| 標準入力を閉じてから process が終了するまで | 1秒 |

Monika は session の最後に extension process の標準入力を閉じます。extension process は
EOF を受け取ったら処理を終え、終了 status `0` で終了しなければなりません。上限時間
までに終了しない場合、Monika は process を強制終了して回収します。

不正な response、上限超過、timeout、途中の EOF、書き込み失敗、および終了 status
`0` 以外は session の失敗です。失敗した session の process は再利用しません。

## 権限

参照実装は Extension process を fail-closed の operating system sandbox で実行します。
通常の Interpreter、Extractor、Auditor、および Deriver に公開するのは、標準入出力の
protocol channel、executable の実行に必要な read-only file、`launchPaths` で明示した
read-only file、および session 固有の scratch 領域です。親 process の workspace access、
任意の filesystem read、filesystem write、および network access は継承しません。scratch
領域は session 終了時に削除し、一つの file に16 MiB の上限を適用します。Linux では
scratch filesystem 全体にも16 MiB の上限を適用します。

Resource Observer だけは `resource-observer` authority を必要とします。この authority は
観測対象の Origin class を `extension` に固定し、`resourceReadPaths` の read-only access と
`network` の許可を明示します。通常 role に Resource Observer authority を与えることと、
Resource Observer を通常の `sandboxed` authority で起動することは、process 起動前に拒否します。
authority は入力 stream の意味的な所有権を移しません。Resource Observer が返した内容は
host が検証して固定した後だけ Observation になります。

macOS は `/usr/bin/sandbox-exec`、Linux は `/usr/bin/bwrap` を使用します。必要な sandbox
機構が存在しない場合は `sandbox-setup-failed` とし、sandbox なしの起動へ切り替えません。
Windows の参照実装は現在 Extension process を実行せず、同じ code で fail-closed にします。
静的 manifest 検査と Extension を起動しない capability 列挙は Windows でも利用できます。

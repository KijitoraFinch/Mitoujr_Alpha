# Extension process 通信の設計意図

## この文書の目的

この文書は、外部 extension process との通信方式について、採用した設計とその理由を
記録します。実装者が従う規則は
[`protocol/extension-protocol.md`](../protocol/extension-protocol.md) に記載します。

この文書で session とは、Monika が一つの extension process を起動し、request と
response を交換し、process の終了を確認するまでを指します。

## 静的 manifest と process の起動を分けます

manifest は capability の種類、名前、version、および適用対象だけを記述します。
executable path と引数は含めません。manifest を workspace に保存しても、それだけで
任意の process が起動されない状態を維持するためです。また、同じ manifest を、
開発時の script、install 後の executable、別の operating system 用 executable と
組み合わせられます。

現在は CLI の `--executable` と `--argument` が両者を関連付けます。install 済み
extension の検索と登録は別の設計事項です。

## shell を介しません

Monika は executable と引数を配列として process API へ渡します。shell command の
文字列は受け取りません。引用符、空白、wildcard、および command substitution の解釈が
shell ごとに変わることと、入力値が意図せず command として評価されることを避けるため
です。

## JSON-RPC 2.0 を使用します

request ID、成功 response、および error response に既存の規則を使用できるため、独自の
request envelope は定義しません。method name には `monika.` prefix を付け、ほかの
JSON-RPC API と同じ process で扱う場合にも名前が衝突しないようにします。

protocol version 1 では request を直列に処理します。同時に複数の request を送らない
ため、extension 側は response の並べ替えや共有状態の同期を実装する必要がありません。
request ID は、余分な stdout 出力や誤った response を検出するためにも使用します。

## 一行を一つの message とします

JSON の文字列内にある改行は escape されるため、LF を message の区切りとして使用
できます。`Content-Length` header の parser を各実装言語で用意する必要がなく、標準の
line reader と JSON library で実装できます。

この方式では一つの message 全体を有限の byte 数に収める必要があります。そのため、
参照実装は16 MiB の上限を設けています。`monika.initializeSession` では Monika と extension
process がそれぞれ扱える最大 byte 数を交換し、小さい方を以後の session の上限に
します。大きな source file、PDF、Parquet data などの内容をこの JSON message へ直接
埋め込むとは決めていません。

## 最初に session を初期化して capability を照合します

最初の method は `monika.initializeSession` です。process が返す protocol version と capability
を静的 manifest と照合します。manifest と異なる executable を指定した場合や、
古い executable が残っている場合に、実際の処理を始める前に停止するためです。

参照実装の通常呼び出し用 API は、この照合が成功した session だけを呼び出し側へ渡し
ます。`monika.initializeSession` より先に別の method を送ることと、同じ session で
`monika.initializeSession` を二回送ることは拒否します。

`acceptedObservationTypes`、`applicability.pathGlobs`、`selectorSchemas`、および
`resultSchemas` は集合として比較します。これらの順序は capability の意味を変えない
ためです。名前、version、schema identity、および field の有無は一致を要求します。

applicability は process 起動後の推測や失敗時 fallback には使用しません。host の
Resource Observer が canonical workspace path と固定された suffix-to-ObservationType
規則から ObservationType を先に確定します。
未知 suffix では、一致する path glob と単一 ObservationType の組だけを明示的な対応として
受理します。`related` は、適用対象 Observation ごとに独立した checked session を
使用します。built-in と extension の候補が重なった場合は、優先順位を設けず曖昧な
dispatch として拒否します。

Interpreter の候補選択は、確定済み ObservationType と path を manifest に照合します。
選択結果から Observation を再構築せず、同じ Observation 値を
`monika.interpretObservation` へ渡します。

## 待機時間と message size を制限します

書き込みと読み取りには一つの終了時刻を使用します。process が stdin を読まない場合、
response を返さない場合、および途中まで書いて停止した場合を、同じ30秒の範囲で終了
させます。response の byte 数は JSON parse 前にも検査します。

session の終了時には stdin を閉じます。process が1秒以内に終了しない場合は強制終了し、
wait を行って process table に残さないようにします。失敗した process は後の request に
再利用しません。

これらの値は参照実装の既定値です。通常コマンドから呼び出す段階では、処理の種類と
利用者の policy に応じた値を明示的に渡せるようにします。

## stdout と stderr の用途を分けます

stdout は protocol 専用です。人間向けの log は stderr に書きます。JSON parser が log
の一部を response として受理することを防ぎ、Monika が error の位置を正確に報告できる
ようにするためです。

stderr は現在 Monika process の stderr を継承します。容量制限のない stderr を Monika
が pipe に保持して、extension process を停止させないためです。log の収集と容量制限が
必要になった場合は、専用の非同期読み取り処理として追加します。

## JSON を受信後にも検査します

JSON Schema による検査だけには依存しません。参照実装は、重複 field、不正な UTF-8、
小数、safe integer の範囲外の値、未知の field、ID の不一致、および `result` と `error`
の同時指定を受信時に拒否します。JSON の入れ子は128段に制限し、parser または検査処理
の call stack を使い切る入力も拒否します。JSON library ごとに既定の受理範囲が異なる
ためです。

## process の権限は制限していません

現在の実装は process の起動と通信を管理しますが、filesystem や network access を
制限する sandbox ではありません。extension が直接書き込まないという規則と、実際に
書き込みを不可能にする仕組みは区別します。信頼できない extension を実行できると説明
してはいけません。

## Observation の内容を host が固定します

意味モデル上、Resource Observer は `Origin` が指す Resource を観測し、固定された
`Observation` または `Failure` を返します。protocol version 1 の
`monika.observeResource` は Extension Origin を exact Resource Observer へ dispatch し、
返された byte 列または構造化値を host 側で検証して固定します。
Interpreter の `interpretObservation` は、
その固定済み Observation から `Interpretation` または `Failure` を返します。
`resolveRegion` は、interpreter、固定された `Observation`、および
`Selector` から `Region` または `Failure` を返します。protocol version 1 の wire
形式では、checked session の manifest によって interpreter を固定し、観測対象を
observation 値と固定された content の組として渡します。`resolveRegion` には、
その組に selector を加えて渡します。意味モデル上の入力と結果は
[`resource-observation-model.md`](resource-observation-model.md) に定めています。

Annotation Extractor と Reference Extractor は固定済み Observation を必須入力とし、
Interpretation は存在する場合だけ受け取ります。Interpreter の dispatch が unsupported でも、
ObservationType に適用可能な Extractor は独立に実行します。このため Interpreter の coverage と
Extractor の成功・失敗を一つの条件分岐へ畳み込みません。

内容本体の転送は、LSP の text document 前提には寄せません。LSP は JSON-RPC 上で
document identity を明示する先例として有用ですが、Monika が扱う対象は text に限られ
ません。そこで、Git、Nix、および OCI image layer のような content-addressed object の
考え方に寄せ、observation の `contentIdentity` を正準の identity として扱います。

byte-backed Observation の request には byte stream descriptor だけを置き、host が直後の
bounded notification で正確な byte 列を送ります。構造化 Observation は schema identity と
正規化済み JSON value を Observation 自体に持ち、content stream を使用しません。Resource
Observer が生成する byte 列は response より前の逆方向 stream で host へ渡します。
filesystem path、URI、および host resource token は Extension へ渡しません。この形により、
次の条件を同時に満たします。

- extension が読む間、内容と ObservationIdentity の対応が変わりません。
- text、binary、および schema 付きの構造化 JSON を区別して表現できます。
- 大きな内容を一つの JSON message へ複製せずに渡せます。
- Extension が Observation の元ファイルを開き直す必要がありません。
- extension が返した Region が入力の Observation に属することを検査できます。

参照実装は、`inspect` の一時 extension 指定から `monika.interpretObservation` を呼びます。
`resolve` は source Observation を担当する Interpreter と、Reference target に記録された
name/version の Interpreter を独立に dispatch します。target の内容は host が安定して読み、
target Interpreter の新しい checked session に渡します。source session の隠れた状態を
target 解決の入力にしません。

install 済み Extension は workspace 外の不変な `RegistrySnapshot` から exact identity で
選びます。Interpreter dispatcher は候補がちょうど一つであることを要求します。
Annotation Extractor と Reference Extractor の dispatcher は適用可能な候補をすべて
canonical capability identity 順に実行し、型別の結果を加算します。Auditor も installed
候補を加算し、Deriver、Resource Observer、および target Interpreter は exact identity
で選びます。候補数と合成規則は capability ごとに明示し、一つの汎用的な優先順位へ
押し込みません。session pool は性能上の追加候補ですが、意味論には含めません。

## host 側の失敗も値として返します

checked session を受け取る host callback が例外を送出した場合、runtime は process を
終了させたうえで、例外を再送出せず `host-operation-exception` failure を返します。
この failure は extension が返す wire 上の failure ではなく、host 内部の session
境界を表す値です。例外文字列は安定した protocol 値ではないため公開しません。

同様に、extension response の decode、manifest の照合、および region の検証に
失敗した場合も、別の observation や selector を代替結果として採用しません。呼び出し側は
明示的な failure を受け取り、CLI 境界で `CommandResult` の diagnostic に変換します。
diagnostic の `extensionFailure` は、失敗した operation、extension 固有の code、および
任意の data を保持します。JSON-RPC error の数値 code と data も、この構造化された
詳細情報から失われません。

# Extension process 通信の設計意図

## この文書の目的

この文書は、外部 extension process との通信方式について、採用した設計とその理由を
記録します。実装者が従う規則は
[`protocol/extension-protocol.md`](../protocol/extension-protocol.md) に記載します。

この文書で session とは、Monika が一つの extension process を起動し、request と
response を交換し、process の終了を確認するまでを指します。

## 静的 descriptor と process の起動を分けます

descriptor は capability の種類、名前、version、および適用対象だけを記述します。
executable path と引数は含めません。descriptor を workspace に保存しても、それだけで
任意の process が起動されない状態を維持するためです。また、同じ descriptor を、
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
参照実装は16 MiB の上限を設けています。`monika.describe` では Monika と extension
process がそれぞれ扱える最大 byte 数を交換し、小さい方を以後の session の上限に
します。大きな source file、PDF、Parquet data などの内容をこの JSON message へ直接
埋め込むとは決めていません。

## 最初に capability を照合します

最初の method は `monika.describe` です。process が返す protocol version と capability
を静的 descriptor と照合します。descriptor と異なる executable を指定した場合や、
古い executable が残っている場合に、実際の処理を始める前に停止するためです。

参照実装の通常呼び出し用 API は、この照合が成功した session だけを呼び出し側へ渡し
ます。`monika.describe` より先に別の method を送ることと、同じ session で
`monika.describe` を二回送ることは拒否します。

`mediaTypes` と `pathGlobs` は集合として比較します。これらの順序は適用条件の意味を
変えないためです。名前、version、schema reference、および field の有無は一致を要求
します。

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

## Observation の内容転送は別に設計します

`observe` は `Origin` から固定された `Observation` または `Failure` を返す操作です。
`resolveRegion` は、interpreter、固定された `Observation`、および `Selector` から
`Region` または `Failure` を返す操作です。これらの入力と結果の意味は
[`resource-observation-model.md`](resource-observation-model.md) に定めています。

ただし、Observation の内容は常に一つの byte string であるとは限りません。元の
workspace path を渡すと、identity を計算した後に file が変更される問題が再発します。
すべての内容を inline JSON にすると、大きな data を扱う際に message size と memory
使用量が増えます。一時 file だけにすると、構造化された外部 API response に不要な
byte serialization を要求します。

そのため、今回の protocol version では内容の渡し方を固定しません。次の実装では、少なく
とも以下を同時に満たす表現を決めてから `observe` と `resolveRegion` を公開します。

- extension が読む間、内容と ObservationIdentity の対応が変わりません。
- text、binary、および schema 付き JSON を表現できます。
- 大きな内容を一つの JSON message へ複製せずに渡せます。
- 大きな内容を指す参照値の有効期間と、session 終了時の解放条件が明確です。
- extension が返した Region が入力の Observation に属することを検査できます。

この判断により、現在の runtime は言語 interpreter を通常コマンドへ登録しません。
実装済みなのは、process の起動、通信、`monika.describe`、制限、および終了処理です。

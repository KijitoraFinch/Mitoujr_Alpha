# 重要
Alphaという名前だがアルファ版ではない。
適当な実装や間に合せの最小実装は原則厳禁、必要な場合はユーザと協議したうえで明示的な形で（そのような実装がされていることが自明となる形で）のみ行います。
できる限り開発用ツールとして高い質を隅々まで維持するのが基本方針（uv, Cargoのように）

## ソフトウェアの概要

この実装の目的は、自然言語文書、ソースコード、実験データ、ログ、Web 由来の内容、未知形式のファイルなどを、同じ種類の「解釈可能な情報」として扱える基盤を作ることです。

特定のファイル形式、特に Markdown を中心に置く設計にはしません。Markdown は重要な編集面ですが、概念上はソースコードや JSONL や任意の blob と同列です。

中心となる機能は、次の通りです。

- workspace 内の情報単位を列挙する
- 情報単位の中の部分領域を解釈する
- 部分領域同士の関係や参照を抽出する
- 参照が現在も解決可能かを検査する
- Markdown inline annotation、source comment、sidecar file の不整合を検出する
- 既存の明示情報から sidecar や inline annotation への編集案を導出する（derive）
- 編集案を安全に適用する
- 後から interpreter、extractor、auditor、deriver を追加できるようにする

重要な設計方針は以下です。

1. 設定ファイルに手続きを書かない

YAML や JSON には、pipeline、steps、if/then、command execution のような手続きを持たせません。
そこに置くのは、参照先、selector、relation、policy、schema version などの値だけです。

2. 書き込みは patch 経由にする

拡張機能や helper は、原則としてファイルを直接書き換えません。
編集案を patch として返し、実際の書き込みは core の apply コマンドだけが行います。

3. Markdown と source code は概念上は特別扱いしないが、標準 helper を厚くする

Markdown と source code は実際に最も頻繁に編集されるため、標準で helper を提供します。
Markdown では拡張されたインラインリンク、HTML comment などを扱います。
Source code では doc comment や言語ごとの symbol 抽出を扱います。

4. sidecar-only は許すが、検出可能にする

sidecar にある annotation が Markdown inline などから derive されないことは、直ちにエラーではありません。
ただし、check コマンドで sidecar-only として検出できる必要があります。

5. derive と infer を分ける

derive は、既に明示された情報から、sidecar や inline annotation への編集案を決定的に導く処理です。
infer は、明示されていない関係や annotation を推測する処理です。
初期実装では derive を core に含め、infer は後から追加できる補助機能として扱います。

最初に固定する CLI は、以下を想定します。

- monika scan
- monika inspect
- monika resolve
- monika check
- monika derive
- monika apply
- monika capabilities
- monika extension test

この実装は薄い試作品ではありません。
後から Web、PDF、Rust、Python、Parquet、実験基盤、検索 index、変更影響解析などを足せるようにするための core です。

## 実装戦略

実装は二段階で行います。

第一段階では、表現力が高い言語で、明快な参照実装を作ります。この実装は、仕様を発見し、データモデルを固め、ゴールデン出力を生成するための完全に動作する実装です。

第二段階では、より高速で配布しやすい言語で、同じ振る舞いを持つ実装を作ります。この実装は、参照実装の出力、診断、スキーマ、ゴールデンテストを基準にします。

この二段階の間には、独立した仕様層を置きます。仕様層は、参照実装の内部構造そのものではなく、外部から観測できる振る舞いを固定します。

仕様層に含めるものは以下です。

- JSON Schema
- 診断コード一覧
- CLI の入出力仕様
- ゴールデンテスト
- 冪等性テスト
- 参照解決の snapshot 形式
- patch 形式
- extension protocol
- 正規化規則

この方針により、最初の実装で設計を明快にし、後続の実装で性能と配布性を得ます。


## DESIGNDOCS
There's DESIGNDOCS in some module directories.
If you are adding a new feature or making significant changes to existing functionality, you should keep the design document updated.

## PLAN
基本、指示されたときのみPLAN.mdを見る。PLAN_GLOBAL.mdは巨大すぎてコンテキストが埋まるし不要なのでみなくて良い

## 日本語ガイドライン
*曖昧な造語や略語、助詞の省略を避け（日本語は助詞が重要です）、明快かつ厳密な日本語を使用してください。* 明確で簡潔な表現を心がけてください。技術用語は一般的に受け入れられているものを使用し、必要に応じて英語の用語も併記してください。

## 開発スタイル
- 基本的には、モダンな関数型のメンタルモデルを強く持ちます。べき等性を保ち、状態を明示的な値として扱うことを重視します。これは言語レベルと言うより設計レベルでも適用されます。
- テスト駆動に近いレベルでテストを整備してから実装を開始します。ただし、テストはある種のバグの発見を行える一方で、テストコード自体がバグの温床になることもあるため、テストコードの品質にも十分注意を払います。

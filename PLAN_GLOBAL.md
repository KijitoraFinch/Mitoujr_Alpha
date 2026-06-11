# トップレベルプラン（更新した場合は commit する）
# 実装計画

## 方針

この実装では、最初から少し厚めに開発基盤を作ります。

理由は、LLM エージェントは実装の勢いが出ると、場当たり的なコードを作りやすいからです。今回の対象は、相互依存したデータ構造、拡張システム、CLI、診断、patch 生成を含みます。したがって、最初に Sugar の意味モデル、観測可能な正規形、テスト、ゴールデン出力、CLI 境界を固定します。

ただし、最初から機能を広げすぎません。最初に作るものは、小さいが中核である必要があります。後から周辺機能を足すだけで広げられる構造にします。

## 実装言語の方針

参照実装(Sugar)と高速実装(Bitter)を分けます。特殊な方法なので、[[AGENTS.md]]の方針を参照してください。

### 参照実装

参照実装は OCaml で作ります。

目的は以下です。

- データモデルを明快に表現する
- 意味モデルを所有する
- 正規化規則を固定する
- 観測可能な正規形を生成する
- CLI の入出力を固定する
- 診断コードを固定する
- ゴールデンテストを生成する
- Bitter 実装が目標にする結果同値性のオラクルとして使う

参照実装は、捨てるためのプロトタイプではありません。仕様を発見し、固定し、検証するための完全に動作する実装です。
遅くても問題ないので、完全に動くこと、そして、場当たり的な抽象の放棄をせず、よいモデルで明快なコードを書くことを優先し、惜しみなくリソースを投入します。

### 高速実装

高速実装は Rust で作ります。

目的は以下です。

- 高速な IO とスキャン
- 配布しやすい単一バイナリ
- 大きなワークスペースへの対応
- extension process との安定した通信
- 参照実装と同じ利用者可視の結果

Rust 実装では、OCaml 実装の内部構造や内部手順をそのまま移植する必要はありません。高速化のために traversal、cache、内部型、処理順序は変えてよいです。重要なのは、同じ workspace、同じ command、同じ policy に対して、利用者から見て同じ結果になることです。

一致させる対象は、以下です。

```text
final workspace content
created / modified / deleted file set
CommandResult の正規形
Diagnostic の正規形
ProposedPatch の正規形
ResolutionSnapshot の正規形
exit class
```

一致を要求しない対象は、以下です。

```text
内部データ構造
内部 traversal order
中間 transaction の分割単位
非公開 trace
性能最適化のための内部 cache
```

## 仕様層

Sugar と Bitter の間には、観測可能な仕様層を置きます。

ただし、この仕様層は Sugar の意味モデルより先に厚く固定しません。まず OCaml の型表現と純粋関数を十分に活用して Sugar の意味モデルを作り、その構築制約と振る舞いをテストします。意味モデルが成立した後に、観測可能な正規形へ写す純粋関数を定義します。JSON Schema は内部モデルではなく正規形を記述し、正規形との不整合を機械的に検出できるようにします。

仕様層に含めるものは以下です。

```text
normal-forms/
  command result
  diagnostics
  proposed patch
  resolution snapshot
  capability

schemas/
  artifact.schema.json
  region.schema.json
  reference.schema.json
  annotation.schema.json
  diagnostic.schema.json
  patch.schema.json
  capability.schema.json
  snapshot.schema.json

golden/
  scan/
  inspect/
  resolve/
  check/
  derive/
  apply/
  workspace-transitions/

diagnostics/
  codes.md

protocol/
  extension-protocol.md

tests/
  normal-form.md
  idempotency.md
  patch-application.md
  selector-resolution.md
  workspace-transition.md
```

Sugar は意味モデルから正規形を生成します。Bitter は、内部手順は違っていても同じ正規形と同じ workspace 遷移を生成することを目標にします。

## Sugar / Bitter 境界の方針

現時点では、Sugar が意味モデルを所有し、正規形を投影する方針を本線にします。

```text
Sugar semantic model
  -> normalize
    -> observable normal form
      -> JSON
      -> JSON Schema
      -> golden
```

Bitter は Sugar と同じ内部型を持つ必要はありません。Bitter は高速化のために Rust に自然な内部表現を使い、正規形、診断、patch、snapshot、workspace transition の観測結果を Sugar と合わせます。

一方で、正規形から外れる workspace 操作を Sugar と Bitter で二重実装することには危険があります。特に、text edit application、path normalization、content identity、atomic write、conflict detection、snapshot cache update は差分が生まれやすいです。

そのため、以下の条件が現れたら、共通 workspace runtime への切り出しを検討します。

```text
apply 周辺で Sugar / Bitter 差分が複数回出る
patch schema が filesystem 実行詳細を抱え始める
failure-mode test を両実装に重複して大量に書く必要がある
atomic write や partial failure recovery が早期に重要になる
正規形が実質的に runtime 命令列になり始める
```

共通 runtime に切り出す場合でも、最初は大きな runtime を作りません。最小 POC は `normalized ProposedPatch -> apply text edits -> normalized CommandResult` に限定します。runtime には annotation、selector、derive、check、policy 判断を入れません。

## フェーズ -1: 記録について
このプロジェクトは、成果物、部分領域、参照、注釈、関係、診断を扱うための基盤を作る。したがって、開発過程の判断や試行錯誤も、できるだけ記録として残したい。

ただし、最小コアが存在しない段階では、Monika 自身による注釈、検査、導出は使えない。したがって、最初の段階では、普通の Markdown と Git 履歴を使って、後から Monika に取り込める原始的な記録を残す。

## 方針

ブートストラップ期の文書は、以下の性質を持つ。

- 普通の Markdown として読める
- 特殊な処理系を必要としない
- 後から Artifact / Region / Annotation / Relation として解釈しやすい
- 決定、未決事項、設計制約、用語、実装結果を分けて記録する
- エージェントが参照しやすい粒度で置く
- 書く負担を増やしすぎない

## 最初に置く文書

最初に以下の文書を置く。

```text
docs/
  overview.md
  architecture.md
  implementation-plan.md
  bootstrap-log.md
  decisions.md
  glossary.md
  invariants.md
  cli-contract.md
  schema-notes.md
  extension-protocol.md
  fixtures.md
```

### docs/overview.md

プロジェクトの目的と全体像を書く。

ここには、以下を書く。

- このプロジェクトが何を作るか
- 文書、コード、データ、ログを同列に扱う理由
- 最初に作る中核
- 最初に作らないもの
- 参照実装と高速実装の関係

### docs/architecture.md

概念モデルを書く。

ここには、以下を書く。

- Artifact
- Region
- Reference
- Annotation
- Relation
- ResolutionSnapshot
- WorkspaceSnapshot
- Diagnostic
- ProposedPatch
- Capability
- Extension

この文書は、実装者が最初に読む設計文書にする。

### docs/implementation-plan.md

実装順序を書く。

ここには、以下を書く。

- OCaml 参照実装
- Rust 高速実装
- 仕様層
- JSON Schema
- ゴールデンテスト
- fixture
- CLI
- extension protocol

### docs/logs/bootstrap-log_連番.md

日々の作業記録を書く。

これは、細かい判断や試行錯誤を捨てないためのログである。多少冗長でもいい。
ただし、長期的な設計判断は DESIGNDOC に昇格させる。

形式は軽くする。

```md
## 2026-06-11

### やったこと

- CLI の中核を `scan / inspect / resolve / check / derive / apply` に整理した
- `materialize` という名前を避け、`derive` を採用する方向にした

### 気づき

- sidecar は正規化表現だが、主たる編集面ではない
- Markdown と source code には標準 helper が必要

### 未決事項

- OCaml 側の JSON Schema 生成方法
- Rust 側とのゴールデンテスト比較方法
```

### DESIGNDOCS

設計判断を記録する。

log よりも安定した内容を書く。
各項目には、できれば日付かコミットハッシュなど、判断、理由、代替案、影響を書く。

形式:

```md
## D-0001: YAML に手続きを書かない

Date: 2026-06-11

### Decision

YAML や sidecar には、処理手順を書かない。
書いてよいものは、参照、selector、binding、expectation、relation などの値だけである。

### Rationale

設定ファイルに steps / pipeline / if / then を持たせると、小さな workflow engine になりやすい。
これはデバッグ、互換性、権限、安全性、冪等性を難しくする。

### Consequences

処理は core と extension が所有する。
extension は capability を登録し、候補、診断、表示、patch を返す。
```


## 最小コア完成後の移行

最小コアが動いたら、ブートストラップ期の文書を Monika の対象にする。

最初に行うこと:

```text
monika scan docs
monika inspect docs/overview.md
monika inspect docs/decisions.md
monika check docs
monika derive docs --to sidecar
```

この時点で、既存の Markdown 文書から sidecar を導出し始める。

ただし、sidecar への移行は一括でやらなくてよい。
まずは 構造が安定している文書から対象にする。

## フェーズ 0: リポジトリ整備

最初に、実装よりも開発基盤を作ります。

作るもの:

```text
/sugar
  参照実装

/bitter
  高速実装の雛形

/schemas
  JSON Schema

/golden
  CLI 出力のゴールデンテスト

/fixtures
  Markdown、TypeScript、JSONL、sidecar のテスト入力

/docs
  設計文書

/protocol
  extension protocol

/diagnostics
  診断コード一覧
```

この段階で、最低限の CI を入れます。

CI で確認するもの:

```text
OCaml 参照実装がビルドできる
schemas が妥当である
fixtures が存在する
golden test を実行できる
Markdown の設計文書が壊れていない
```


## フェーズ 1: Sugar の意味モデルと正規形

まず、JSON Schema や JSON encoding を先に厚く固定するのではなく、Sugar 内に意味モデルを作ります。意味モデルは OCaml の代数的データ型、module、抽象型などを必要に応じて使い、純粋関数で操作します。不正な状態を表現しにくい型と、意味上の構築制約を検査するテストを先に整備します。

この段階で作るもの:

```text
Artifact
Region
Reference
Annotation
Relation
ResolutionSnapshot
Diagnostic
ProposedPatch
CommandResult
```

意味モデルとそのテストが成立した後に、意味モデルから観測可能な正規形へ写す関数を作ります。

```text
normalize_artifact
normalize_region
normalize_reference
normalize_annotation
normalize_diagnostic
normalize_patch
normalize_snapshot
normalize_command_result
```

正規形は、golden、JSON output、JSON Schema、Bitter との比較に使います。内部モデルそのものを JSON や JSON Schema に合わせません。

診断コードもこの段階で固定します。

初期診断コード:

```text
sidecar-only
inline-only
divergent
stale-selector
duplicate
unreferenced-ref
unresolved-ref
expectation-failed
invalid-sidecar
invalid-selector
unsupported-artifact
```

この段階では、実装はまだ薄くてよいです。重要なのは、Sugar の意味モデル、正規形、診断コード、CommandResult の境界を固定することです。

JSON Schema の実現方法は PPX や特定の library に固定しません。生成、codec からの導出、独立定義のいずれを選ぶ場合も、正規形との不整合を機械的に検出し、手動同期だけに依存しないことを要件とします。

## フェーズ 2: OCaml 参照実装の CLI

OCaml で、以下のコマンドを動作させます。

```text
monika scan
monika inspect
monika resolve
monika check
monika derive
monika apply
monika capabilities
```

最初の対象は、以下に限定します。

```text
Markdown
sidecar YAML
JSON
JSONL
blob
TypeScript等どれか一つの言語
```

この段階では、高速である必要はありません。意味モデルから正規形へ写す経路が明快で、テスト可能で、仕様として信頼できることを優先します。

## フェーズ 3: inspect の完成

`inspect` を最初に厚く作ります。

理由は、エージェントが最も頻繁に使う確認コマンドだからです。

`inspect` が返すもの:

```text
artifact descriptor
regions
refs
annotations
materialization
provenance
diagnostics
```

Markdown では、以下を認識します。

```text
見出し
段落
Markdown link
HTML comment による region id
HTML comment による annotation id
```

source code では、最初は以下を認識します。

```text
関数またはトップレベル symbol
doc comment
@monika tag
```

JSONL では、以下を認識します。

```text
ファイル全体
行範囲
単純な row-filter selector
```

## フェーズ 4: check の完成

`check` は、canonical annotation graph へ正規化してから比較します。

文字列比較ではなく、正規化後の annotation を比較します。

最初に実装する診断:

```text
sidecar-only
inline-only
divergent
stale-selector
duplicate
unreferenced-ref
unresolved-ref
expectation-failed
```

重要な方針:

```text
sidecar-only は初期値では info
inline-only は初期値では warning
divergent は error
stale-selector は error
unresolved-ref は error
duplicate は warning
```

policy ファイルで severity を変更できるようにします。

## フェーズ 5: derive と apply

`derive` は、既に明示された情報から編集案を作ります。

最初に作る derive:

```text
Markdown inline link -> sidecar entry
Markdown HTML comment -> sidecar region entry
source comment @monika -> sidecar annotation
sidecar entry -> Markdown HTML comment
```

`derive` は直接書き込みません。`ProposedPatch` の正規形を返します。

`apply` は patch を適用します。

`apply` の要件:

```text
対象ファイルが変更されていたら conflict にする
同じ patch を二回適用して不要な変更を出さない
適用結果を CommandResult の正規形で返す
initial workspace と final workspace を比較できる
```

この段階では、workspace 操作はまず Sugar 内で実装します。ただし、後から共通 workspace runtime に切り出せるように、text edit application、path normalization、content identity、conflict detection は独立した module に分けます。

## フェーズ 6: extension protocol の最小化

最初は外部 extension を多く作りません。しかし、protocol の形は早めに固定します。

最小 protocol:

```text
describe
canInterpret
listRegions
resolveSelector
extractAnnotations
fingerprintRegion
derive
audit
render
```

通信方式は、最初は JSON-RPC over stdio でよいです。

extension は直接書き込みません。ファイル変更が必要なら patch を返します。

## フェーズ 7: ゴールデンテスト

OCaml 参照実装から、以下のゴールデン出力を作ります。golden は stdout JSON だけではなく、必要に応じて workspace transition も含めます。

```text
monika scan fixtures/basic
monika inspect fixtures/basic/docs/linking.md
monika inspect fixtures/basic/src/resolve.ts
monika check fixtures/basic
monika derive fixtures/basic/docs/linking.md --to sidecar
monika apply golden/derive/linking-to-sidecar.expected.json
monika resolve ref:latency-run-a
```

Rust 実装は、内部手順が異なっていても、このゴールデンで定義された観測結果に一致する必要があります。

ただし、日時、絶対パス、hash のような環境依存値は正規化します。

## フェーズ 8: Rust 実装

Rust 実装は、最初から全機能を作らず、ゴールデンテストを一つずつ通します。

順序:

```text
scan
inspect for blob
inspect for Markdown
inspect for sidecar
check
derive
apply
resolve
extension protocol
```

Rust 側では、内部表現を効率に合わせて変えてよいです。外部 JSON、診断コード、ProposedPatch、ResolutionSnapshot、CommandResult、workspace transition の観測結果が同じであることを重視します。

## フェーズ 9: 参照実装との継続的比較

OCaml 参照実装と Rust 実装を継続的に比較します。

CI で行うこと:

```text
同じ fixture に対して OCaml と Rust の scan 出力を比較する
同じ fixture に対して inspect 出力を比較する
同じ fixture に対して check 出力を比較する
同じ fixture に対して derive 出力を比較する
同じ initial workspace に対して apply 後の final workspace を比較する
patch 適用後に再度 check する
derive -> apply -> derive が空になることを確認する
```

この比較により、Rust 側が意図せず利用者可視の結果同値性から外れることを防ぎます。

## 最初に作る fixture

最初の fixture は小さく、しかし中核の性質を含めます。

```text
fixtures/basic/
  docs/linking.md
  docs/linking.annotations.yaml
  src/resolve.ts
  runs/metrics.jsonl
```

含めるケース:

```text
Markdown inline link
sidecar-only annotation
inline-only annotation
divergent annotation
stale selector
unreferenced ref
unresolved ref
source comment annotation
JSONL pinned reference
```

この fixture が通れば、中核のかなりの部分が検証できます。

## 最初に避けるもの

初期中核では、以下を避けます。

```text
高度な自然言語推論による annotation infer
複雑な Web crawler
PDF の精密 layout 解析
複数言語の高度な LSP 統合
大規模 index の最適化
自動修復の直接適用
設定ファイル内の workflow
```

これらは後から追加します。中核には入れません。

## 完了条件

最初の中核の完了条件は以下です。

```text
OCaml 参照実装で scan / inspect / resolve / check / derive / apply が動く
意味モデルから観測可能な正規形を生成できる
JSON Schema が正規形から生成または検証される
診断コードが固定されている
fixtures/basic が存在する
derive -> apply -> check が動く
derive -> apply -> derive が空になる
apply の workspace transition golden が存在する
sidecar-only を検出できる
inline-only を検出できる
divergent を error として検出できる
stale-selector を error として検出できる
Rust 実装が少なくとも scan / inspect / check のゴールデンテストに追随し始めている
```

この状態になれば、周辺機能を追加しても中核を大きく変えずに済みます。

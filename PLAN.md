# 次にやること

目的は、Phase 0 の scaffold から、Sugar の意味モデルと観測可能な正規形を持つ Phase 1 へ進めることです。まず OCaml の型表現と純粋関数を十分に活用して意味モデルを作り、正規形や JSON の都合から内部モデルを逆算しません。

方針は B を本線にします。つまり、Sugar が意味モデルを所有し、そこから観測可能な正規形を生成します。Bitter は内部手順を合わせるのではなく、利用者から見て同じ結果になることを目標にします。

C、つまり共通 workspace runtime への切り出しは、今は実装しません。ただし、後から切り出せるように、workspace 操作の module 境界と transition test は最初から置きます。

## 1. DESIGN.md に方針を反映する

- `CommandResult` を中核モデルに追加する。
- `Diagnostic` と `CommandResult` の違いを書く。
- 「正規形」は転送用の別概念ではなく、意味モデルから写す観測可能な値であることを書く。
- Sugar / Bitter の一致基準を、内部手順の一致ではなく結果同値性として定義する。
- 共通 workspace runtime は本線ではなく、切り出し条件付きの逃げ道として書く。

完了条件:

- `DESIGN.md` だけ読んでも、B 本線と C 逃げ道の関係が分かる。
- `docs/sugar-bitter-boundary-options.md` と矛盾しない。

## 2. Sugar の最小 module 境界を作る

まだ実機能は薄くてよい。先に境界を作る。

作る module 候補:

- `Model`
- `Command_result`
- `Diagnostic`
- `Proposed_patch`
- `Resolution_snapshot`
- `Workspace_snapshot`
- `Workspace_ops`

責務:

- `Model`: 意味モデルの中心型。
- `Command_result`: コマンド実行全体の結果。
- `Diagnostic`: 問題、不整合、警告。
- `Proposed_patch`: 書き込み前の編集案。
- `Resolution_snapshot`: 参照または領域を解決した時点の結果。
- `Workspace_snapshot`: transition golden 用の workspace 状態。
- `Workspace_ops`: text edit、path normalization、content identity など、後で C に切り出せる部分。

完了条件:

- Sugar が build できる。
- 型の構築制約と純粋関数を検査するテストがある。
- まだ実処理が薄くても、module 境界と型の意図が明確である。

## 3. 意味モデルから正規形への境界を作る

- 手順 2 の意味モデルとテストが成立してから `Normal` を追加する。
- 最初は `CommandResult` と `Diagnostic` の正規形だけを対象にする。
- 内部意味モデルから正規形への変換を、明示的な純粋関数として定義する。
- 内部意味モデルを JSON 表現や JSON Schema generation の都合に合わせない。
- JSON codec と JSON Schema の実現方法は、PPX、codec library、手書き実装を含めて正規形の設計後に選ぶ。

完了条件:

- Sugar から最小 `CommandResult` JSON を出せる。
- 意味モデルが JSON の型や encoding に依存していない。
- JSON Schema の生成方法にかかわらず、正規形との不整合を機械的に検出する方針が文書化される。

## 4. 結果同値性の golden 形式を決める

stdout JSON だけでは足りないため、workspace transition golden の最小形式を決める。

必要な観測対象:

- initial workspace snapshot
- command
- normalized stdout JSON
- normalized diagnostics
- normalized proposed patches
- final workspace snapshot
- exit class

完了条件:

- `golden/` に normal-form golden と transition golden の置き場所がある。
- `tools/check_golden.py` が、最低限その形を検査できる。

## 5. apply 周辺の切り出し候補を純粋関数として作る

C へすぐ移行しないが、後から切り出せるようにする。

最初に分けるもの:

- path normalization
- content identity
- text edit application
- conflict detection
- workspace snapshot normalization

完了条件:

- Sugar 内では純粋関数としてテストできる。
- filesystem への直接書き込みとは密結合していない。
- C に移る場合の境界が見える。

## 6. C へ移る条件をテストで監視する

以下が起きたら、共通 workspace runtime の POC を検討する。

- apply 周辺で Sugar / Bitter 差分が複数回出る。
- patch schema が filesystem 実行詳細を抱え始める。
- failure-mode test を両実装に重複して大量に書く必要がある。
- atomic write や partial failure recovery が早期に重要になる。
- 正規形が実質的に runtime 命令列になり始める。

完了条件:

- `docs/sugar-bitter-boundary-options.md` と `PLAN_GLOBAL.md` に同じ判断基準がある。
- `PLAN.md` の次回更新時に、B 継続か C POC かを判断できる。

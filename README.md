# Alpha

Alpha は、自然言語文書、ソースコード、ログ、実験データ、Web 由来の内容、
未知形式の blob などを、同じ種類の「解釈可能な情報」として扱うための基盤
Monika の開発リポジトリです。リポジトリ名の Alpha は、ソフトウェアの成熟度を
表すものではありません。

現在のリポジトリは Phase 1 の状態です。Phase 0 の開発基盤は整備済みであり、
Sugar には `monika scan`、`monika inspect`、`monika resolve`、
`monika check`、`monika derive`、`monika apply` の実行可能な参照実装に加え、
capability の検出と静的な extension descriptor の検査が含まれています。
これらは、意味モデル、観測可能な正規形、artifact descriptor、patch 入力の
厳密な decode、純粋な workspace 遷移、読み取り専用の workspace scan、
および既存の通常ファイルを編集する際のファイルシステム境界を実装しています。

Schema version 4 では、正規化された capability observation を追加しました。
Schema version 3 では、型を持つ artifact 内の observation ID、未解決の region
address、inspect 結果の envelope を確定しました。最初の inspect interpreter
は CommonMark のコメントとリンクを抽出し、宣言的な sidecar v1 形式を厳密に
decode します。

最初の check auditor は、JSONL の各行に対して厳密な filter を実行し、stale、
unresolved、expectation、representation、unused-reference の各状態を報告します。
inline annotation から sidecar を導出する処理は、identity guard を持つ patch を
返します。そのべき等性は、実際の `derive -> apply -> derive` サイクルによって
検査されます。

参照解決では、正規化された UTC の観測時刻を明示する必要があります。結果は、
決定的に再現できる snapshot として出力されます。

`monika capabilities` は、組み込みの artifact provider、interpreter、
annotation extractor、deriver、auditor を、ほかのコマンドと同じ厳密な結果
envelope で報告します。

ファイルシステムを扱う実装には、handle-relative traversal と
クロスプラットフォームの安全性検査が定義されています。ただし、同時に変更される
workspace や敵対的な workspace に対して安全であるとは、まだ見なせません。
詳細は [PLAN.md](PLAN.md) を参照してください。pre-alpha 配布で保証する範囲と、
配布までに残っている gate は
[pre-alpha 配布準備状況](docs/pre-alpha-readiness.md) に記載しています。

Agent は通常、解釈済みの artifact を一件読む場合に `monika read` を使用し、
workspace 内の入力関係または出力関係を調べる場合に `monika related` を使用します。
正規化された JSON protocol は `monika inspect` などのコマンドから引き続き
利用できます。`monika related --json` は、問い合わせに必要な範囲へ絞った
graph result を出力します。

最初の pre-alpha 配布は、公開 opam package ではなく、Codex を使用する組織内の
利用者へソースコードを引き渡す形式です。Codex へそのまま渡せる導入・更新指示と、
source package の取り扱い手順は
[Codex 向け導入ガイド](docs/codex-installation.md) に記載しています。

配布物には、検証済みソースへの更新と問題報告を行う Codex Skill も含まれます。
`monika-update` は更新先を完全な revision として解決し、rollback に必要な状態を
保持して、新しい package を検証した後に同梱された二つの Skill を更新します。
`monika-report` は Codex session 一件分の生のログ、機密情報を除去した環境情報、
導入済みの Monika version を収集し、機密 bundle を非公開の report inbox へ
送信できます。各 Skill の責務と境界は、
[Codex を使用する更新](docs/codex-update-skill.md) と
[Codex を使用する問題報告](docs/codex-reporting.md) に記載しています。

## ローカル検査

```sh
make phase0-check
make golden-check
make build-sugar
make distribution-check
make check-bitter
```

`make check` は、すべての検査を実行します。

`make release-check` は、これらに加えて、公開 package 用 metadata の gate を
実行します。Codex を使用する組織内配布では、`make check` と
クロスプラットフォームの CI matrix を使用します。公開配布には、maintainer、
authors、license の metadata を別途定義する必要があります。

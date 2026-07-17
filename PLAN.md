# 次の実装計画

## 目的

現在の Sugar 実装を、安定したローカル workspace で動く参照実装から、並行変更や
プラットフォーム差を含めて安全性を説明できる core へ進めます。`inspect` の実装を
急ぐ前に、`scan` と `apply` が共有する filesystem 境界と、跨言語で一致させる値の
契約を固定します。

## 現状

実装済みの主な機能は以下です。

- 検証済み constructor を中心とする Sugar の意味モデル。
- `CommandResult` の正規形、JSON encoder、および schema version `"4"`。
- diagnostic、patch、snapshot、artifact、command-result の厳密な JSON Schema。
- 純粋な `WorkspaceSnapshot` と決定的な text patch application。
- strict `ProposedPatch` decoder と、単一の既存 file を対象とする `monika apply`。
- regular file を列挙し、内容を bounded memory で hash する `monika scan`。
- normal-form、scan、pure workspace-transition の golden。
- duplicate JSON key、型の混同、逆転 range、非 canonical path を検出する仕様検証。
- install 可能な `monika` executable と、追跡対象の opam package manifest。
- temporary prefix へ package を install し、install 済み `monika capabilities`
  を golden と照合する distribution smoke test。
- Bitter scaffold に対する `cargo fmt --check`、`clippy`、`test`、stdout smoke test。
- POSIX の `scan` と `apply` が共有する descriptor-relative filesystem adapter。
- `scan` の hash 前後の file state 比較、1 回の bounded retry、安定した変更失敗。
- POSIX temporary file の descriptor-relative 作成、権限変更、flush、`renameat`。
- POSIX directory flush の未対応エラーと実際の失敗の分類。
- 実 `monika apply` を temporary workspace で実行する end-to-end golden と、
  `exitClass` に対応する numeric process exit code。
- JSON safe-integer domain と UTF-8 Unicode scalar domain の共有 corpus、および Sugar、
  JSON Schema/specification validator、Bitter の同一分類。

レビューで明らかになり、今回修正した事項は以下です。

- scan root が symbolic link の場合の誤った internal error。
- scan の I/O 例外漏れと、読取り不能 file を warning success にする挙動。
- scan が artifact 全体を memory に読み込む実装。
- 空の artifact media type を意味モデルだけが許す schema 不整合。
- workspace path の raw byte 順と canonical string 順の不一致。
- command-result の `status`、`exitClass`、diagnostic default severity の schema 不足。
- required `artifacts` collection を古い schema version `"1"` に追加する互換性違反。
- 未実装 schema が任意の object を受理する fail-open scaffold。
- fixture 内の workspace path と `fixtures/basic` workspace root の不一致。
- clean checkout で opam manifest が存在せず、CLI も install 対象でなかった CI 構成。

ただし、filesystem の安全性については次の重大な未解決事項があります。

- Windows の retained-handle traversal、reparse-point rejection、handle-relative
  temporary creation と replacement は実装したが、Windows 実機 CI の結果をまだ
  観測していない。
- Linux、macOS、Windows の CI matrix と、held-parent、reparse point、case folding、
  Unicode normalization の platform-gated integration test は構成済みだが、macOS と
  Windows の実行結果をまだ観測していない。

したがって、現行の `scan` と `apply` は実行可能な参照 slice ですが、並行変更される
workspace や信頼できない workspace に対する production-safe な境界とはまだ呼びません。

## 実装順序

### 1. Handle-based filesystem 境界を固定する（最優先の release gate）

`scan` と `apply` が共有する小さな platform adapter を設計します。

- POSIX では workspace root と各 parent directory の file descriptor を保持し、
  `openat`、`fstatat`、`renameat`、no-follow semantics を使用する（実装済み）。
- Windows では wide-character root API、`NtCreateFile` の `RootDirectory`、directory/
  file handle を使用し、各段階で reparse point を拒否する（実装済み、実機 CI 未確認）。
- temporary file の権限変更と flush は path ではなく開いた handle に対して行う
  （POSIX は実装済み）。
- directory flush の「未対応」と実際の失敗を区別し、後者を `applied` にしない。
  POSIX 実装に加え、置換、parent flush、read-back の各失敗を明示的な commit state
  machine へ通し、rename 後 failure を決定的に注入する test を実装済みである。
- scan は inspect と同じ read handle を再利用できる形にし、hash 中の変更を検出する。
  変更時は 1 回再試行し、再び変更された場合は安定した failure を返す
  （POSIX と、成功・再失敗の両方を扱う決定的な bounded retry test は実装済み）。

完了条件は、directory 差し替え、file-to-symlink 差し替え、FIFO、reparse point、
rename 後 failure を fault injection で再現し、workspace root 外の read/write がなく、
曖昧な状態を success と報告しないことです。Linux、macOS、Windows の CI job を必須に
します。3 platform の CI matrix 自体は構成済みです。

### 2. 跨言語の値 domain と意味型を固定する

Sugar、Bitter、JSON Schema が同じ値集合を受理するように、次を独立した仕様として
決めます。

- size、offset、range、row-filter integer、summary count の幅と符号。JSON safe-integer
  domain に固定し、共有 corpus による三者の分類を実装済みである。
- schema-visible string の UTF-8 検証。Unicode scalar UTF-8 に固定し、共有 corpus による
  三者の分類を実装済みである。任意 byte replacement は将来の明示的な base64/hex
  variant とし、text string へ混在させない。
- `Artifact_id` と `Patch_id` は別の抽象型へ移行済みである。`Artifact_id` は
  workspace-global、`Patch_id` は command-scoped とする。artifact-local な
  `Region_id`、`Reference_id`、`Annotation_id` は異なる抽象型とし、version 3 の
  `{artifact, local}` scoped object として固定済みである。
- `Conflict.t` は private variant と検証 constructor に変更済みである。
- JSON Schema で表せない `range.end >= range.start` などを、配布可能な semantic
  validator として仕様層に置く。

完了条件は、境界値と不正 UTF-8 を含む同一 corpus を Sugar decoder、schema validator、
Bitter decoder が同じ結果に分類することです。

### 3. 実 CLI の end-to-end golden を追加する（基本ケースは実装済み）

現在の apply workspace-transition golden は `Workspace_ops.apply_patch` を直接呼び、CLI
argument parser、JSON decoder、`Filesystem_apply`、stdout envelope を通りません。
temporary workspace 上で実際の `monika` executable を起動する harness を追加し、
success、dry-run、repeated no-op、各 conflict、invalid input、I/O failure の stdout、
exit class、final bytes を同時に固定します。numeric process exit code もこの段階で決定します。
I/O failure は OS の strerror や native absolute path を canonical message にせず、stable code
と workspace-relative location を持つ結果にします。

現時点では success、dry-run、repeated no-op、identity/range/overlap/result identity
conflict、invalid input、target lock の I/O failure を実 executable で検証し、stdout、
final bytes、`success=0`、`diagnostic-error=1`、`usage-error=2`、`internal-error=3` を
固定しました。apply の I/O failure は stable `errorCode`、operation、workspace-relative
location を持ち、native absolute path と OS error text を正規形に含めません。

### 4. `inspect` の契約と最初の interpreter（実装済み）

filesystem と値の gate を通過した後、実装より先に次を固定します。

- workspace root と canonical workspace-relative artifact を必須にする CLI input。
- 未解決の `RegionAddress` を失わずに保持する `Region_ref` / `Region_address`。
- artifact-local ID と workspace-global ID の scope、および重複拒否。
- `regions`、`annotations`、`references` を observation として表す正規形、canonical
  ordering、厳密 schema、encoder-generated golden。
- collection 追加に伴う command-result schema version 3。
- extraction と resolution の分離。`inspect` は明示情報を抽出しますが、参照解決や
  `infer` は行わない。

最初の interpreter は retained-handle read、CommonMark comment、Markdown inline link、
厳格な sidecar v1 decoder を実装し、実 CLI golden で固定しました。詳細は
`docs/inspect-interpreter.md` に記録します。source comment は同じ protocol を使う次の
interpreter とし、特定形式を core の概念に埋め込みません。

### 5. `check`、`derive`、Bitter parity へ進む

最初の selector resolution と `check` は、厳格な JSONL row-filter と Markdown region ID
を対象に実装し、sidecar-only、inline-only、divergent、stale-selector、
unreferenced-ref、unresolved-ref の golden を実 CLI 出力へ置き換えました。詳細は
`docs/check-auditing.md` に記録します。deterministic な inline-to-sidecar `derive` も
実装し、`derive -> apply -> derive` が二回目に patch を返さないことを実 CLI で検証します。
詳細は `docs/derive-sidecar.md` に記録します。
`resolve` は暗黙の wall clock を使わず、canonical RFC 3339 UTC の `--observed-at` を
必須入力として snapshot を実出力へ置き換えました。詳細は
`docs/resolve-snapshot.md` に記録します。

Bitter は広い移植から始めません。既に追加した format、lint、test、scaffold smoke test を
維持し、schema version `"4"` の scan と pure patch transition から Sugar との
differential test を開始します。

`monika capabilities` は、実装済みの組込み機能を version 4 の capability observation
として列挙し、standalone schema、semantic validator、実 CLI golden で固定済みです。
次の extension slice では descriptor と protocol version の検証を実装し、extension に
workspace の直接書込み権限を与えない境界を実行可能にします。

## 後続事項

Pre-alpha の配布範囲、各 gate の証拠、および所有者の判断が必要な項目は
`docs/pre-alpha-readiness.md` に固定します。設定済みの CI job を実行済みの証拠とは
扱いません。

create/delete patch、複数 patch transaction、persistent snapshot cache、Web/PDF/Parquet
interpreter は、上記の safety・value-domain・inspect contract が固定された後に進めます。
設定 file に手続きを導入せず、すべての書込みを core の patch apply 境界へ集約する原則は
維持します。homepage、bug report URL、development repository は Git remote に基づいて
固定済みです。package を公開する前に、maintainer、authors、license を所有者の判断で
固定し、`opam lint` を release gate に追加します。

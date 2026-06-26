# 次にやること

目的は、Sugar の Phase 1 で固めた `ProposedPatch`、`CommandResult`、
`Workspace_ops.apply_patch` を使い、`monika apply` の最小実装に進むことです。
この段階では、`scan`、`inspect`、`resolve`、`check` へ広げる前に、patch 入力、
CLI envelope、filesystem 書き込み境界を品質高く固定します。

## 現状

完了済みの主な土台は以下です。

- Sugar の意味モデル。
- `CommandResult` の観測可能な正規形。
- diagnostic、patch、snapshot、command-result の schema。
- 純粋な `WorkspaceSnapshot` と deterministic text patch application。
- normal-form golden と workspace-transition golden。

未完了の主な領域は以下です。

- patch JSON を入力として読む decoder。
- production CLI としての `monika apply`。
- 実 filesystem に対する安全な書き込み境界。
- create/delete patch。
- `scan` 以降の artifact traversal、selector resolution、Bitter parity。

## 今回の実装目標

今回の目標は、以下の 3 項目を実装可能な仕様として固め、実装することです。
4 番目以降の transition golden 拡充と `scan` は、この 3 項目が成立した後に進めます。

## 1. ProposedPatch JSON decoder を追加する

`Normal_json` は出力 encoder として維持します。入力用には別 module を置き、
JSON を内部 record に直接詰めず、必ず semantic layer の smart constructor を通します。

対象にする入力は以下です。

- workspace path
- content identity
- text range
- text edit
- provenance
- proposed patch

この decoder は、`Normal_json.patch` が出力する observable patch 形を読むことを
最初の契約にします。patch file の外側 envelope はまだ増やしません。

完了条件:

- patch JSON から `Proposed_patch.t` を構築できる。
- 不正な path、identity、range、空 edits、空 reason、空 provenance source を拒否する。
- `null`、不足 field、余分な field、型違いを診断可能な decoder error として返す。
- decoder test が schema-visible な境界値を検査している。

## 2. `monika apply` の CLI 契約を小さく固定する

最初に固定する呼び出しは以下です。

```sh
monika apply --workspace <dir> --patch <file> --dry-run
monika apply --workspace <dir> --patch <file>
```

`--patch <file>` は 1 個の `ProposedPatch` JSON を指します。複数 patch、stdin、
patch set、create/delete patch はこの段階では扱いません。

`--dry-run` は filesystem を変更しません。適用可能な場合は、入力 patch を
`patches` に含む `patches-proposed` result を返します。すでに
`resultingContentIdentity` と同じ内容であれば、`ok` result を返します。
conflict がある場合は、通常の apply と同じ `conflict` result を返します。

numeric exit code は Phase 2 の判断として残し、この段階では JSON の
`exitClass` を正とします。

完了条件:

- 成功、dry-run、no-change、conflict、invalid input が `CommandResult` で表現される。
- stdout は schema version `"1"` の command result JSON だけを出す。
- CLI parse error、patch decode error、workspace root error は `invalid-input` になる。
- `CommandResult.effect` と payload 排他制約を破らない。

## 3. filesystem 境界を設計してから実装する

実 filesystem への書き込みは、純粋な `Workspace_ops.apply_patch` の後に置く境界です。
この境界は間に合わせにしません。実装前に
[apply filesystem boundary](docs/apply-filesystem-boundary.md) の設計を満たします。

最低限固定する policy は以下です。

- workspace root 外参照を拒否する。
- target path と parent path の symlink policy を明示する。
- Linux、macOS、Windows の native path mapping 差を明示する。
- containment 判定に文字列 prefix 判定を使わない。
- Windows の reserved name、reserved character、reparse point を拒否する。
- case-insensitive filesystem と Unicode normalization の扱いを固定する。
- 既存 regular file への text edit だけを対象にする。
- 同一内容なら no-change とし、書き込みを行わない。
- write は同一 directory 内の temporary file と atomic rename で行う。
- 失敗時に partial write を残さない。
- non-cooperating external writer との競合限界を文書化し、Monika apply 同士は
  per-target lock で直列化する。
- 安全に表現できない filesystem failure は、成功扱いにしない。

完了条件:

- `--workspace` の root 解決と patch target 解決が、root 外へ出ないことを検査している。
- symlink、directory、non-regular file、missing file の扱いがテストで固定されている。
- POSIX、Windows、macOS で差が出る path、symlink/reparse point、case folding、
  Unicode normalization のテスト方針が固定されている。
- write 前に expected identity を検査し、write 後に resulting identity を検査している。
- replacement 直前にも expected identity を再検査している。
- no-change の場合に file mtime や content を変更しない。
- write failure の test が、元 file の内容保持を検査している。

## 3 項目の後に進めること

次の段階では、workspace transition golden を増やします。対象は少なくとも以下です。

- identity mismatch
- range out of bounds
- overlapping edits
- result identity mismatch
- repeated apply no-op

その後、`scan` を workspace traversal policy と artifact descriptor schema を固定する
段階として進めます。

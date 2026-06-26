# 次にやること

目的は、Sugar の `ProposedPatch`、`CommandResult`、`Workspace_ops.apply_patch`
を土台にした最初の実 `monika apply` slice を固定し、その後に `scan` へ進むことです。

## 現状

完了済みの主な土台は以下です。

- Sugar の意味モデル。
- `CommandResult` の観測可能な正規形。
- diagnostic、patch、snapshot、command-result の schema。
- 純粋な `WorkspaceSnapshot` と deterministic text patch application。
- `Normal_decode` による strict `ProposedPatch` JSON decoder。
- `monika apply --workspace <dir> --patch <file> [--dry-run]` の最小 CLI。
- `Filesystem_apply` による実 filesystem apply 境界。
- normal-form golden と apply workspace-transition golden。

未完了の主な領域は以下です。

- create/delete patch。
- 複数 patch の transaction。
- Windows/macOS 実機での platform-gated filesystem test。
- `scan` 以降の artifact traversal、selector resolution、Bitter parity。

## Apply Slice の固定内容

### 1. ProposedPatch JSON decoder

`Normal_json` は出力 encoder として維持し、入力用には `Normal_decode` を置きます。
decoder は JSON を内部 record に直接詰めず、必ず semantic layer の smart
constructor を通します。

対象にする入力は以下です。

- workspace path
- content identity
- text range
- text edit
- provenance
- proposed patch

decoder は `Normal_json.patch` が出力する observable patch 形を読みます。patch
file の外側 envelope はまだ増やしません。`null`、不足 field、余分な field、
型違い、不正な path、identity、range、空 edits、空 reason、空 provenance
source は invalid input です。

### 2. `monika apply` の CLI 契約

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

### 3. Filesystem 境界

実 filesystem への書き込みは、純粋な `Workspace_ops.apply_patch` の外側に置きます。
境界の詳細は [apply filesystem boundary](docs/apply-filesystem-boundary.md) にあります。

実装済みの policy は以下です。

- `--workspace` root を物理 path に解決する。
- patch target を segment ごとに解決し、文字列 prefix 判定で containment を証明しない。
- symlink target、symlink parent、Windows reparse point を安全拒否する。
- Windows reserved name、reserved character、invalid UTF-8 segment を拒否する。
- directory、device、FIFO など non-regular target を安全拒否する。
- 同一内容なら no-change とし、書き込みを行わない。
- write は同一 directory 内の temporary file、flush、platform replace、read-back verify で行う。
- replacement 直前にも expected identity を再検査する。
- Monika apply 同士は system temp 配下の per-target lock で直列化する。
- filesystem safety failure は `filesystem-safety` conflict として観測可能にする。

## Apply Transition Golden

workspace transition golden は以下を固定しています。

- `apply-title-replacement`
- `apply-identity-mismatch`
- `apply-range-out-of-bounds`
- `apply-overlap`
- `apply-result-identity-mismatch`
- `apply-repeated-no-op`

## 次の段階

次は `scan` を workspace traversal policy と artifact descriptor schema を固定する段階として進めます。
その前に apply をさらに固める場合は、Windows/macOS 実機での reparse point、case folding、
Unicode normalization、replace-existing semantics の integration test を追加します。

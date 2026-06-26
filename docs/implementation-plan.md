# Implementation Plan

The top-level plan is kept in [PLAN_GLOBAL.md](../PLAN_GLOBAL.md). This file
records the completed bootstrap and current Phase 1 boundary.

## Phase 0 Deliverables

- `sugar/`: OCaml reference implementation scaffold.
- `bitter/`: Rust high-speed implementation scaffold.
- `schemas/`: valid JSON Schema scaffold files.
- `golden/`: golden-output locations for each CLI family.
- `fixtures/basic/`: the first fixture corpus and case inventory.
- `docs/`: bootstrap documentation.
- `protocol/`: extension protocol notes.
- `diagnostics/`: diagnostic code registry.
- `tools/check_phase0.py`: local Phase 0 verifier.
- `tools/check_golden.py`: scaffold golden-output verifier.
- `.github/workflows/phase0.yml`: minimum CI entry point.

## Phase 1 Status

Sugar now provides the semantic model, command result normal form, concrete
diagnostic/patch/snapshot schema definitions, pure workspace snapshots, and
deterministic text-patch application. Normal-form and workspace-transition
goldens are generated from the OCaml implementation.

The OCaml semantic model is implemented and tested before observable schemas are
changed. The semantic reference model represents digest expectations with
validated `Content_digest` values. Row-filter selectors use a non-empty abstract
map of validated field names to typed literals; the selected interpreter owns
resolution semantics. Normal forms and schemas are projections of these types,
not inputs to their design.

Production CLI behavior, selector resolution, filesystem writes, create/delete
patches, and Bitter parity remain later work.

## Next Implementation Target: Apply

The next implementation target is the first production-quality `monika apply`
slice in Sugar. This slice deliberately comes before `scan`, `inspect`,
`resolve`, and `check`, because the repository already has the semantic patch
model, command-result envelope, pure workspace transition behavior, and apply
transition golden structure.

This target covers exactly three implementation areas:

1. A `ProposedPatch` JSON decoder for patch input.
2. A small `monika apply` CLI contract.
3. A designed and tested filesystem boundary for applying text edits.

The patch decoder must consume the same observable patch shape emitted by
`Normal_json.patch`, but it should live outside `Normal_json`. The decoder is an
input boundary and must construct semantic values through `Workspace_path`,
`Content_identity`, `Text_range`, `Text_edit`, `Provenance`, and
`Proposed_patch` constructors rather than bypassing invariants.

The initial CLI contract is:

```sh
monika apply --workspace <dir> --patch <file> --dry-run
monika apply --workspace <dir> --patch <file>
```

`--patch` names a file containing one `ProposedPatch` JSON object. Patch sets,
stdin input, create/delete patches, and multi-file transactions are later work.
Numeric process exit codes also remain a later decision; the authoritative
observable outcome is `CommandResult.exitClass`.

Filesystem writes must be implemented only after the boundary documented in
[apply-filesystem-boundary.md](apply-filesystem-boundary.md) is satisfied. The
minimum policy rejects references outside the workspace root, defines symlink
handling, avoids writes for no-op content, uses same-directory temporary files
and atomic rename for replacement, and does not report success when partial or
ambiguous write failure occurs. The boundary is cross-platform: it must define
native path mapping for POSIX-like systems and Windows, reject Windows reparse
points and reserved names, avoid string-prefix containment checks, account for
case-insensitive and Unicode-normalizing filesystems, and document the
concurrency limits around non-cooperating external writers.

After this apply target, the next planning unit is expanded workspace-transition
goldens for apply conflicts and repeated no-op behavior. `scan` follows after
the apply filesystem boundary and CLI envelope are stable.

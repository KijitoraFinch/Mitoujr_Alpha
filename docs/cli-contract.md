# CLI Contract Notes

The initial CLI family is:

- `monika scan`
- `monika inspect`
- `monika resolve`
- `monika check`
- `monika derive`
- `monika apply`
- `monika capabilities`
- `monika extension test`

Phase 1 fixes the JSON result envelope with schema version `"1"`.

Every result contains `diagnostics`, `patches`, `changedArtifacts`, `conflicts`,
and `snapshots` arrays, including when they are empty. `summary` is omitted when
no summary was generated; an empty object means a summary was generated with no
entries. Optional observations are omitted and are not encoded as `null`.

Paths are workspace-relative, slash-separated, and percent-encoded by byte.
Collections are sorted by semantic canonical keys before encoding.

`status` and `exitClass` are derived from command termination, effect, and
effective diagnostic severity. Numeric process exit codes remain a Phase 2
decision.

The command result payload is constrained by `effect`. `No_change` has no
patches, changed artifacts, or conflicts. `Patches_proposed` has non-empty
patches and no changed artifacts or conflicts. `Applied` has non-empty changed
artifacts and no patches or conflicts. `Conflicted` has non-empty conflicts and
no patches or changed artifacts.

## `monika apply`

The first production CLI contract for apply is intentionally small:

```sh
monika apply --workspace <dir> --patch <file> --dry-run
monika apply --workspace <dir> --patch <file>
```

`--workspace <dir>` identifies the workspace root used to resolve patch targets.
`--patch <file>` contains exactly one `ProposedPatch` JSON object in the same
observable shape emitted by `Normal_json.patch`.

Workspace containment and target resolution are platform-specific filesystem
operations, not string-prefix checks. If the target cannot be mapped safely to a
native path under the workspace root on the current platform, apply returns
`invalid-input` or a filesystem safety failure; it must not silently rewrite a
different native path. Filesystem safety failures are returned as `conflict`
results with `kind: "filesystem-safety"` and a stable `reason` enum.

The patch file is not a command result and does not carry its own
`schemaVersion` field in this milestone. It contains:

- `id`
- `target`
- `expectedContentIdentity`
- `resultingContentIdentity`
- `edits`
- `reason`
- `provenance`

Patch JSON decoding is strict. Missing fields, unknown fields, `null`, type
mismatches, invalid workspace paths, invalid content identities, invalid ranges,
empty edit lists, empty reasons, and empty provenance sources are invalid input.

Without `--dry-run`, apply reads the target file, checks the expected content
identity, applies text edits, verifies the resulting content identity, and then
writes the replacement through the filesystem boundary. A successful write
returns an `applied` result with `changedArtifacts`. If the current content
already matches `resultingContentIdentity`, apply returns an `ok` result and
does not write the file.

With `--dry-run`, apply performs the same decoding, workspace-root validation,
target safety checks, expected identity check, edit application, and resulting
identity verification, but it does not write. If the patch would apply, the
result is `patches-proposed` and contains the input patch. If the target already
has the resulting content, the result is `ok`. If a conflict is found, the
result is `conflict`, as in non-dry-run apply.

CLI parse errors, patch decode errors, and invalid workspace roots produce
`invalid-input`. Patch conflicts produce `conflict`. Numeric process exit codes
remain a Phase 2 decision; consumers should use `exitClass`.

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

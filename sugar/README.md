# Sugar

Sugar is the OCaml reference implementation. Phase 1 defines the semantic model,
observable normal form, JSON encoder, artifact descriptors, read-only workspace
scanning, pure workspace transition behavior, and the first executable
`monika inspect`, `monika resolve`, `monika check`, `monika derive`, and
`monika apply` slices.
`monika capabilities` exposes normalized built-in capability descriptors, and
`monika extension test --descriptor` strictly validates the non-executing
protocol version 1 descriptor boundary. With an explicitly supplied executable,
Sugar also performs bounded live `monika.describe` matching; temporary
interpreter paths in `inspect` and `resolve` exercise `monika.observe` and
same-session `monika.resolveRegion`.

The library is intentionally layered:

```text
semantic model -> Normal -> Normal_json
workspace snapshot + proposed patch -> Workspace_ops -> workspace snapshot
retained workspace bytes -> Markdown_inspect + Sidecar_v1 -> observations
observations + interpreter resolution -> Workspace_check -> diagnostics
observations + sidecar source locations -> Workspace_derive -> proposed patch
```

Semantic modules do not depend on Yojson. Read-only file enumeration is kept
behind `Workspace_scan`. Absent-target creation and existing-file edits for
`monika apply` are kept behind `Filesystem_apply`, while pure patch semantics
remain in `Workspace_ops`.
`Workspace_inspect` reads through `Workspace_read`; CommonMark and the
YAML-preserving AST are parser boundaries rather than semantic model types.

The OCaml semantic model is the source of truth. Sugar core represents row
filters as non-empty abstract maps from validated field names to typed literals
and dispatches their format-specific semantics to the interpreter named by the
target. Core directly resolves broadly shared selector forms. Reference
expectations use the closed `Expectation` algebra and validated content digests.
Normal forms, encoders, schemas, and goldens are derived only after those
semantic types and invariant tests are established.

Artifact origins, reference targets, and command results are also protected by
constructors. Empty schema-visible strings are rejected before normalization,
all schema-visible text uses Unicode scalar UTF-8, protocol integers use the
JSON safe-integer domain, and command-result effects determine which payload
collections may be non-empty. Artifact and patch identifiers are distinct
abstract types, and conflict values use validated constructors.

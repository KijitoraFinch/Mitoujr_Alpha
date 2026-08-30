# Sugar

Sugar is the OCaml reference implementation. It defines the semantic model,
observable normal form, JSON encoder, fixed observations and Sidecar snapshots,
typed indexes, immutable workspace graph snapshots, read-only workspace
scanning, and pure workspace transition behavior for the CLI.
`monika capabilities` exposes normalized built-in capability objects, and
`monika extension test --manifest` strictly validates the non-executing
protocol version 1 manifest boundary. With an explicitly supplied registry,
Sugar performs bounded `monika.initializeSession` matching and dispatches
Resource Observers, Interpreters, Annotation Extractors, Reference Extractors,
Auditors, Derivers, and Region extent operations by their role-specific rules.

The library is intentionally layered:

```text
semantic model -> Normal -> Normal_json
Origin -> Resource Observer -> fixed Observation
Sidecar file -> SidecarSnapshot -> SidecarContents
Observation -> Interpreter / Extractors -> typed indexes
fixed inputs + registry -> WorkspaceGraphSnapshot
WorkspaceGraphSnapshot + AuditPolicy -> diagnostics
WorkspaceGraphSnapshot + DeriveRequest -> proposed patches
workspace snapshot + proposed patch -> Workspace_ops -> workspace snapshot
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

Observation origins, reference targets, and command results are also protected by
constructors. Empty schema-visible strings are rejected before normalization,
all schema-visible text uses Unicode scalar UTF-8, protocol integers use the
JSON safe-integer domain, and command-result effects determine which payload
collections may be non-empty. Observation and patch identifiers are distinct
abstract types, and conflict values use validated constructors.

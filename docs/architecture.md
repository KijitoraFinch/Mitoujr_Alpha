# Architecture

The core model is described in [DESIGN.md](../DESIGN.md). This document records
the current Phase 1 architecture boundary.

## Core Concepts

- Resource: a possibly changing target that Monika attempts to observe.
- Origin: a declarative value used to identify a resource again.
- Observation: one finite, typed result fixed for the duration of an operation.
- Artifact: the current command-envelope adapter for a content-backed
  observation, not the general definition of an observation.
- Region: the whole or a selectable part of exactly one observation.
- Reference: a value that targets an artifact or region.
- Annotation: information attached to a region.
- Relation: a semantic relationship between regions, references, or values.
- Snapshot: the observed result of resolving a reference at a point in time.
- Diagnostic: a stable report about inconsistency or invalid state.
- Patch: an edit proposal that can be applied only through core commands.
- Capability: an extension-provided operation with a narrow contract.

The language-neutral responsibilities and their reference implementation
mapping are specified in
[resource-observation-model.md](resource-observation-model.md).

## Phase 1 Boundary

Sugar owns the semantic model and maps it to a separately typed observable
normal form. Only the normal form is encoded as JSON. This prevents JSON
representation choices from leaking into interpretation and workspace logic.

Phase 1 fixes:

- workspace-relative logical path normalization
- SHA-256 content identity
- byte-offset text ranges and edits
- required selectors on region targets, including explicit `whole-artifact`
  targets and non-empty `row-filter.where`
- typed reference expectations, initially digest expectations
- private origin and reference-target constructors for schema-visible strings
- diagnostic severity and command result derivation
- effect-specific command-result payload invariants
- stable normal-form ordering
- artifact descriptors in command results
- type-qualified observation identities and versioned interpreter identities in
  the semantic model
- exact region-resolution inputs composed from interpreter, observation, and
  selector values
- extension origins for providers such as GitHub Issue observers
- artifact-local typed region, reference, and annotation IDs
- unresolved `RegionAddress` values distinct from resolved region IDs
- version 6 command results, retaining version 5 create/edit patches and adding
  extension origins, extension selectors, and interpreter-free whole regions
- pure workspace snapshot and patch application behavior
- read-only workspace scanning for existing regular files
- retained-handle artifact reads shared by the first inspect slice
- CommonMark region/annotation comments and fragment-bearing link extraction
- ownership-aware declarative sidecar v1 decoding and Markdown/sidecar
  reference merging
- pure JSONL row-filter execution and the first workspace check auditors
- deterministic inline-to-sidecar patch derivation
- explicit-time reference resolution snapshots
- Agent-facing workspace graph queries that distinguish named reference
  declarations, actual reference occurrences, and predicate-bearing relations
- normalized built-in capability discovery
- strict, non-executing extension descriptor contract testing
- strict `ProposedPatch` JSON input decoding for `monika apply`
- the filesystem apply boundary for safe creation and existing regular-file
  edits

Broader selector families and runtime extension execution remain outside this
boundary. The inspect boundary is specified in
[inspect-interpreter.md](inspect-interpreter.md), and selector auditing is
specified in [check-auditing.md](check-auditing.md). Sidecar patch construction
is specified in [derive-sidecar.md](derive-sidecar.md). Resolution snapshots are
specified in [resolve-snapshot.md](resolve-snapshot.md). The current filesystem
work is split into narrow boundaries:
`Workspace_scan` recursively reads regular files and reports unsupported entries
such as symlinks as diagnostics. Its immutable traversal policy composes
per-directory `.gitignore` and `.monikaignore` rules without consulting
repository-external Git state. `Filesystem_apply` validates workspace
containment under a stable directory topology, rejects unsafe write targets
such as symlinks below the workspace root, preserves existing file mode where
supported, uses same-directory
temporary replacement, and treats safety failures as conflicts.

The current boundaries and their concurrency limits are specified separately in
[scan-filesystem-boundary.md](scan-filesystem-boundary.md) and
[apply-filesystem-boundary.md](apply-filesystem-boundary.md). POSIX and Windows
now use the shared handle-relative adapter. Remote Windows and macOS execution
of the platform-specific containment, reparse, case-folding, and Unicode-folding
tests still blocks a cross-platform safety claim.

`Workspace_inspect` uses `Workspace_read` for the primary artifact and optional
sidecar, so interpretation never falls back to a native path lookup after
containment checks. Markdown syntax and source locations come from CommonMark;
the sidecar decoder works from the YAML-preserving AST so aliases, anchors,
explicit tags, duplicate keys, unsafe numeric values, and unknown fields are
rejected before semantic construction.

Sugar core owns selector construction and normalization. Interpreters own
selector resolution semantics. In particular, core preserves a row filter as a
non-empty abstract map from validated field names to typed literals and does not
expose an interpreter-specific `column`/`equals` execution model. Digest
expectations contain validated `Content_digest` values rather than encoded
strings.

Every semantic region retains the identity of the observation from which it was
resolved. Command-result construction rejects a region attached to an artifact
descriptor for a different observation. The interpreter name and version,
observation identity, and selector form the comparable resolution input.

Region targets always carry a selector. An entire artifact is represented by
`whole-artifact`; a full byte range is still a byte range and is not normalized
into `whole-artifact`. Broadly shared addressing modes can become core selector
variants. Extension-specific addressing uses a named schema and normalized JSON
value, so new resource kinds do not require a core release.

The OCaml semantic model and its invariant tests are the source of truth for the
reference implementation. Normal forms, encoders, schemas, and goldens follow
that model; fixture syntax does not define the internal OCaml representation.
This does not make OCaml an extension ABI. Runtime extensions exchange
language-neutral, schema-versioned values and may be implemented in any
language.

Distribution verification is kept outside the semantic core. It copies the
Sugar source into an isolated tree, builds in Dune package mode without the
workspace `_build`, stages the install set into a temporary prefix, and executes
the installed binary. Undeclared parent-tree dependencies, missing install
declarations, and runtime-linking regressions therefore fail before a release
archive is produced.

Binary release construction is a second distribution boundary, not part of
workspace semantics. A compile-time release identity binds the CLI to one
SemVer and commit prefix. Platform jobs execute the relocated CLI before
upload. The assembly job admits exactly four target binaries and one
deterministic Skill archive, then derives a closed release manifest and
`SHA256SUMS`. For each successful `pre-alpha` push, the GitHub workflow derives
an immutable SemVer prerelease tag from the commit timestamp and commit ID and
publishes it only after the closed asset set passes verification. The manual
path accepts an existing immutable tag and creates only a draft prerelease;
promotion on that path remains an explicit owner action.

Artifact origins and reference targets are constructed through smart
constructors. Empty strings that would later violate the observable schema, such
as git repositories, git paths, web URLs, generated names, external URIs, and
interpreters, are rejected in the semantic layer.

Every `ProposedPatch` carries a resulting content identity. Edit patches also
carry the expected input identity; create patches instead carry complete
content and require an absent target. The result identity recognizes repeated
application as a no-op without hidden mutable state.

The Agent-facing query layer is a projection over immutable workspace
observations rather than a replacement for the command-result protocol.
`Reference` declarations, syntactic `ReferenceOccurrence` values, and semantic
`Relation` values remain distinct. Its first workspace-level query and
query-specific JSON boundary are fixed in
[agent-query-api.md](agent-query-api.md).

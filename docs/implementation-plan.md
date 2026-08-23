# Implementation Plan

The current prioritized plan is [PLAN.md](../PLAN.md). `PLAN_GLOBAL.md` is not
required for day-to-day implementation work.

## Completed Foundation

- `sugar/`: OCaml reference implementation and installable `monika` CLI.
- `bitter/`: checkable Rust implementation scaffold.
- `schemas/`: strict command-result, diagnostic, patch, snapshot, observation, and
  capability schemas with shared definitions.
- `golden/`: generated normal-form, scan, and pure workspace-transition oracles.
- `fixtures/basic/`: the first fixture corpus, with paths relative to the corpus
  workspace root.
- `tools/`: repository, schema, semantic, strict-JSON, and golden checks.

Sugar provides the semantic model, command-result schema version `"7"`, pure
workspace snapshots and patch semantics, strict single-patch decoding, an
executable filesystem apply slice for safe creation and existing-file edits,
and bounded-memory regular-file scan. Selectors remain structured values. Core
resolves broadly shared forms and dispatches format-specific forms to the
selected built-in or extension interpreter.

The apply transition corpus is also executed end to end through the built
`monika` executable in temporary workspaces. The harness checks stdout, numeric
process exit code, and final file bytes in addition to the pure transition.

The distribution harness copies only `sugar/` into an isolated temporary source
tree, builds it in Dune package mode, runs its tests, verifies that opam manifest
generation is stable, and stages the result into a temporary prefix. It then
checks the executable, library metadata, opam manifest, and documentation
inventory and runs the installed `monika capabilities` against its golden. It
does not reuse the workspace `_build` tree or install into the developer's
active opam switch.

The binary-release harness validates SemVer tags and full commit identities,
embeds `<version>+<commit-prefix>` into each Sugar executable, executes each
relocated CLI, and emits Linux x86-64, macOS arm64, macOS x86-64, and Windows
x86-64 assets. It creates one deterministic, closed-inventory Skill archive,
then derives and revalidates `release-manifest.json` and `SHA256SUMS`.
Tamper, duplicate-entry, version, target, and inventory boundaries are covered
by `tools/test_release_assets.py`. On `pre-alpha`, the workflow derives a
deterministic SemVer prerelease identity from the commit timestamp and commit
ID, and publishes only after every platform and assembly check succeeds. The
manual immutable-tag path stops at a draft prerelease so promotion remains
deliberate.

## Current Safety Boundary

The scan and apply slices are executable references. POSIX and Windows now use
a shared handle-relative adapter for traversal, regular-file reads,
temporary-file creation, flushing, and replacement. Scan detects a file
mutation during hashing with one bounded retry, and apply does not suppress real
directory-flush failures. Windows runtime verification is still required. The
remaining limitations are specified in
[scan-filesystem-boundary.md](scan-filesystem-boundary.md) and
[apply-filesystem-boundary.md](apply-filesystem-boundary.md).

The mandatory shared handle-relative filesystem unit is implemented as follows:

1. POSIX `openat`/`fstatat`/`renameat` with no-follow behavior. Implemented;
   replacement and post-replacement fault-injection coverage is implemented.
2. Windows handle traversal, reparse-point rejection, handle-relative temporary
   creation, and handle-relative replacement are implemented; Windows CI
   execution remains required.
3. Temporary metadata and flushing use the open file handle. Windows explicitly
   classifies parent-directory flush as unsupported because it has no POSIX
   directory-`fsync` equivalent.
4. Mutation detection while scan hashes content is implemented on POSIX; a
   deterministic bounded-retry fault-injection test covers both recovery and
   repeated mutation failure.
5. Linux, macOS, and Windows jobs are configured as a CI matrix. Held-parent,
   reparse-point, case-folding, and Unicode-folding tests are platform-gated;
   remote macOS and Windows execution has not yet been observed.

Implementation of this unit is complete in the checkout. Remote macOS and
Windows execution of the platform-specific tests remains a release-evidence
gate, not optional hardening.

## Specification Gate Established for Inspect

Before `inspect` was added, the specification layer fixed:

- the numeric domain shared by OCaml, Rust, JSON Schema, and JSON consumers is
  fixed to the JSON safe-integer range and covered by one shared corpus;
- schema-visible text is Unicode scalar UTF-8 and covered by one shared corpus;
  arbitrary-byte replacement requires a future tagged payload variant;
- observation and patch IDs are distinct abstract types; observation-scoped region,
  reference, and annotation IDs and unresolved region addresses are implemented
  as part of the version 3 inspect contract;
- conflict construction uses a private variant and validated constructors;
- constraints JSON Schema cannot express are implemented in the standalone
  semantic validator used by the golden checker;
- end-to-end apply golden tests that execute the installed CLI rather than only
  the pure patch engine cover apply, no-op, conflicts, dry-run, and invalid
  input; deterministic target-lock I/O failure also fixes the stable failure
  normal form and unchanged final bytes.

Schema versioning follows [schema-versioning.md](schema-versioning.md). Version
3 adds the inspect observation collections to the closed command-result object;
version 4 adds capability observations, version 5 adds create/edit patches,
version 6 adds extensible origin and selector values, and version 7 exposes the
general observation shape directly without a content-only wrapper.

## Inspect Slice

The inspect contract and first executable extraction slice now fix the CLI
input, retained-handle reads, unresolved `RegionAddress`, scoped IDs,
region/annotation/reference observation collections, canonical ordering, strict
schemas, and a real CLI golden. Extraction stays separate from resolution and
inference.

Markdown comments, Markdown inline links, and strict sidecar v1 are the first
standard interpreter surfaces. Source comments follow through the same
extension boundary. The detailed contract is in
[inspect-interpreter.md](inspect-interpreter.md). The first selector resolution
and `check` slice now executes JSONL row filters and replaces the six-code basic
check scaffold with a real CLI golden; see
[check-auditing.md](check-auditing.md). Deterministic inline-to-sidecar `derive`
and its `derive -> apply -> derive` idempotency check are also executable; see
[derive-sidecar.md](derive-sidecar.md). `resolve` now requires an explicit
canonical UTC observation time and shares selector execution with `check`; see
[resolve-snapshot.md](resolve-snapshot.md). Sugar/Bitter differential tests
follow.

Create patches are implemented across the semantic model, strict decoder,
derive path, pure workspace transition, filesystem apply boundary, and real CLI
goldens. Delete patches, multi-patch transactions, persistent snapshot caches,
and additional observation families remain later units; they do not bypass the
handle-based apply boundary or introduce procedures into configuration.

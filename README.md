# Alpha

Alpha is the working repository for Monika, a foundation for treating documents,
source code, logs, experimental data, web captures, and unknown blobs as
interpretable artifacts.

The current repository state is Phase 1. The Phase 0 development scaffold is in
place, and Sugar now contains executable reference slices for `monika scan`,
`monika inspect`, `monika resolve`, `monika check`, `monika derive`, and
`monika apply`, plus capability discovery and static extension descriptor
testing: the semantic model, observable normal form, artifact descriptors,
strict patch input decoding, pure workspace transition behavior, read-only
workspace scanning, and the filesystem boundary for existing regular file
edits. Schema version 4 adds normalized capability observations; version 3
fixed typed artifact-local observation IDs, unresolved region addresses, and
the inspect result envelope. The first inspect
interpreter extracts CommonMark comments and links and strictly decodes the
declarative sidecar v1 format.

The first check auditors execute strict JSONL row filters and report stale,
unresolved, expectation, representation, and unused-reference conditions.
Inline-to-sidecar derivation returns an identity-guarded patch and is checked
through a real `derive -> apply -> derive` idempotency cycle.

Reference resolution requires an explicit canonical UTC observation time and
emits deterministic snapshots.

`monika capabilities` reports the built-in artifact provider, interpreters,
annotation extractors, deriver, and auditor through the same strict result
envelope.

The filesystem slices still have documented handle-relative traversal and
cross-platform safety gates. They must not yet be treated as safe for
concurrently mutated or adversarial workspaces; see [PLAN.md](PLAN.md).
The exact pre-alpha distribution claim and its remaining release gates are in
[pre-alpha readiness](docs/pre-alpha-readiness.md).

The first pre-alpha distribution is an internal source handoff for recipients
using Codex, not a public opam package. The copyable setup request and the
source installation procedure are in the
[Codex installation guide](docs/codex-installation.md).

## Local Checks

```sh
make phase0-check
make golden-check
make build-sugar
make distribution-check
make check-bitter
```

`make check` runs all checks.
`make release-check` additionally runs the deferred public-package metadata
gate. Internal Codex-assisted handoff uses `make check` and the cross-platform
CI matrix; public distribution still requires maintainer, authors, and license
metadata.

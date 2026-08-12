# Golden Outputs

This directory records observable normal forms and workspace transitions.
The original command scaffolds have been replaced. `scan`, `inspect`, `resolve`,
`check`, `derive`, and `capabilities` are Phase 1 goldens generated through the
Sugar CLI.

`normal-form/` values are generated from OCaml semantic fixtures and validated
against JSON Schema. `workspace-transitions/` values contain the schema version,
case ID, initial snapshot, command, normalized command result, final snapshot,
and exit class. Diagnostics and patches occur only inside the command result
except for the patch that is itself the transition command input.

The scan goldens fix deterministic regular-file enumeration for the basic
fixture and `.gitignore`/`.monikaignore` composition, nested precedence,
negation, and excluded-directory traversal for the ignore fixture. The inspect
golden fixes retained-handle reads, CommonMark comments and links, strict
sidecar v1 decoding, scoped observation IDs, and normalized provenance. The
check golden fixes JSONL row-filter execution and the six basic
annotation/reference diagnostic codes. The derive golden fixes the
inline-to-sidecar patch, and its harness applies the patch before requiring a
no-op second derivation. The resolve golden fixes explicit-time JSONL selection,
artifact identity, selected-row fingerprint, and display. The apply transition
set fixes title replacement,
identity mismatch, range out of bounds, overlapping edits, result identity
mismatch, and repeated apply no-op behavior.

`cli/` contains outputs exercised through the built `monika` executable. The
apply harness materializes a temporary workspace and checks stdout, process
exit code, and final bytes. The inspect harness runs the basic fixture through
the same built executable. These complement, rather than replace, the pure
workspace-transition oracle. The I/O-failure case makes target-lock creation
fail deterministically and fixes the stable error code, operation,
workspace-relative location, empty effect payload, exit class, and unchanged
workspace bytes. Native absolute paths and operating-system error text are not
part of that normal form.
The capabilities golden fixes the normalized inventory, schema version,
standalone descriptor schema, semantic uniqueness rule, stdout, and process
exit code.
The extension-test goldens cover a valid static descriptor, rejection of an
unsupported protocol version, and a successful `monika.describe` exchange with
a Python process through the real CLI. The extension-inspect golden covers an
ad hoc interpreter extension invoked by `inspect`, including `monika.observe`
dispatch and normalized extension selector regions. The extension-resolve
golden fixes `monika.observe` followed by `monika.resolveRegion` in one checked
session, exact target observation validation, and snapshot normalization.

`related/` fixes the Agent-facing workspace graph projection independently of
the command-result envelope. It covers syntactic reference occurrences,
predicate-bearing semantic relations, broken targets, stale source selectors,
coverage completeness, canonical ordering, and the compact related-result
schema.

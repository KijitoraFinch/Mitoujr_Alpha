# Check and Selector Auditing

`monika check` constructs one fixed WorkspaceGraphSnapshot from primary
Observations, SidecarSnapshots, typed indexes, ReferenceUse edges, endpoint
resolution, graph diagnostics, and Coverage. The built-in Auditor and installed
Auditors consume that value without rescanning the workspace and emit diagnostics
without changing files.

## Selector Resolution

The initial resolver supports:

- `whole-observation` for a safely readable target;
- `text-range` when its half-open byte range remains inside the target;
- `region-id` when the target Markdown interpreter emitted that scoped region;
- `row-filter` for a target explicitly interpreted as `jsonl`.

The JSONL interpreter reads Unicode scalar UTF-8, requires each non-blank line
to be one JSON object, rejects duplicate object keys and non-finite numbers, and
compares selector string, safe-integer, and boolean literals without coercion.
Zero matching rows are unresolved; more than one matching row is an invalid
selector. Digest expectations apply to the entire target observation identity,
not only the selected JSONL row.

Resolution used by `check` is deliberately separate from
`ResolutionSnapshot`: auditing does not invent an observation timestamp. The
`resolve` CLI instead requires a reproducible caller-supplied `observedAt`
value, as fixed in [resolve-snapshot.md](resolve-snapshot.md).

## Annotation Audits

An unresolved annotation subject produces `stale-selector`. For a valid
subject, an annotation ID present on only one materialization surface produces
`sidecar-only` or `inline-only`. A sidecar annotation that has the same resolved
subject as an inline annotation but a different predicate or object produces
`divergent`; the more specific divergence replaces a sidecar-only diagnostic
for that record.

Reference use is collected from explicit ReferenceUse occurrences and from
Annotation objects that name a Reference. An unused definition
produces `unreferenced-ref`; a missing observation or selector with no match
produces `unresolved-ref`; malformed or ambiguous selector execution produces
`invalid-selector`; and a resolved observation whose identity violates a digest
expectation produces `expectation-failed`.

The basic real CLI golden fixes `sidecar-only`, `inline-only`, `divergent`,
`stale-selector`, `unreferenced-ref`, and `unresolved-ref`, together with
diagnostic severities, Coverage, and process exit code 1. `--extension-registry`
adds applicable external Auditors; their diagnostics are validated against the
requested AuditPolicy and added in canonical order. `--policy <file>` loads a
closed `audit-policy.schema.json` value. `sidecarOnly: "allow"` suppresses that
diagnostic code, and every `severityOverrides` entry determines the effective
severity of both built-in and extension diagnostics.

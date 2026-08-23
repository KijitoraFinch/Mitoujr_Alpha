# Check and Selector Auditing

The first executable `monika check` slice audits the explicit observations
produced by standard Markdown and sidecar interpreters. It scans the workspace,
re-reads interpreted observations through the retained-handle boundary, and emits
diagnostics without changing files.

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

Reference use is collected from annotation objects. An unused declaration
produces `unreferenced-ref`; a missing observation or selector with no match
produces `unresolved-ref`; malformed or ambiguous selector execution produces
`invalid-selector`; and a resolved observation whose identity violates a digest
expectation produces `expectation-failed`.

The basic real CLI golden fixes one each of `sidecar-only`, `inline-only`,
`divergent`, `stale-selector`, `unreferenced-ref`, and `unresolved-ref`, along
with diagnostic severities and process exit code 1.

# Reference Resolution Snapshot

The first executable `monika resolve` slice resolves one reference declared by
an inspected workspace observation and emits a `ResolutionSnapshot`.

```sh
monika resolve \
  --workspace <dir> \
  --observation <canonical-workspace-path> \
  --reference <local-reference-id> \
  --observed-at <canonical-RFC3339-UTC>
```

All options are required and occur once. `--observed-at` must use the canonical
second-precision UTC form such as `2026-07-17T00:00:00Z`. Resolve never reads the
wall clock implicitly. Consequently, identical workspace bytes and identical
command arguments produce an identical snapshot and golden output.

Resolve shares `Reference_resolver` with `check`. The initial selectors are
whole observation, bounded text range, emitted Markdown region ID, and strict
JSONL row filter. A JSONL snapshot records the entire observation identity, the
selected row as display text, and the selected row's SHA-256 fingerprint. A
missing target produces `unresolved-ref`; malformed or ambiguous execution
produces `invalid-selector`.

The supplied timestamp describes when the caller says the observation was
made. It is not evidence of an atomic workspace snapshot: source inspection and
target reading are individually stable retained-handle reads, while unrelated
files can still change between those reads.

An explicitly supplied interpreter extension replaces built-in source
inspection for this command. Monika calls `monika.interpretObservation` for the source and
`monika.resolveRegion` for the selected workspace target in one checked process
session. The manifest identity and selector schema must match the reference.
The response region is accepted only when its observation observation identity,
selector, interpreter identity, and byte range match the exact target input.
The resulting snapshot still records the reference target rather than the
extension's region ID, so repeated resolution is compared by the declarative
address and observed target identity.

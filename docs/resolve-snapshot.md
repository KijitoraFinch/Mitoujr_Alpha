# Reference Resolution Snapshot

The first executable `monika resolve` slice resolves one reference declared by
an inspected workspace observation and emits a `ResolutionSnapshot`.

```sh
monika resolve \
  --workspace <dir> \
  --observation <canonical-workspace-path> \
  --reference <local-reference-id> \
  --observed-at <canonical-RFC3339-UTC> \
  [--previous-snapshot <snapshot.json>]
```

The first four options are required and every option occurs at most once.
`--observed-at` must use the canonical second-precision UTC form such as
`2026-07-17T00:00:00Z`. Resolve never reads the wall clock implicitly.
Consequently, identical workspace bytes and identical command arguments produce
an identical snapshot and golden output.

`--previous-snapshot` reads one standalone, normalized `ResolutionSnapshot` as
strict UTF-8 JSON with a 1 MiB limit. It is valid only for a Tracking Reference,
and its target must equal that Reference's complete RegionAddress. Pinned and
Floating References reject the option as invalid input.

Resolve shares `Reference_resolver` with `check`. The initial selectors are
whole observation, bounded text range, emitted Markdown region ID, and strict
JSONL row filter. A JSONL snapshot records the entire observation identity, the
selected row as display text, and the selected row's SHA-256 fingerprint. A
missing target produces `unresolved-ref`; malformed or ambiguous execution
produces `invalid-selector`.

Fingerprints are schema-named normalized values. The built-in byte and JSONL
selectors use `sha256-fingerprint.schema.json`; an Extension Interpreter may use
another declared fingerprint schema. A fingerprint is not interchangeable with
a ContentIdentity or Resource revision.

Pinned resolution requires at least one expectation on the RegionAddress or
Reference and validates every applicable expectation after the selected Region
has been resolved. The supported evidence domains are ObservationIdentity,
ContentIdentity, schema-named Origin revision, and schema-named Region
fingerprint. A mismatch produces `expectation-failed` and no snapshot.

Tracking without `--previous-snapshot` produces a baseline snapshot. With a
previous snapshot, it compares the complete target, ObservationIdentity, and
optional Region fingerprint. A difference emits the current snapshot together
with the warning diagnostic `resolution-changed`; display text and `observedAt`
are evidence metadata and do not by themselves constitute drift. Floating
always resolves the current value without comparison to saved observation
identity.

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

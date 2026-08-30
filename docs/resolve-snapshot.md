# RegionAddress and Reference Resolution Snapshot

`monika resolve` resolves either one normalized RegionAddress directly or one
Reference declared by an inspected workspace Observation. A successful result
contains the fixed target Observation, the resolved Region, and a
`ResolutionSnapshot`.

```sh
monika resolve \
  --workspace <dir> \
  --observation <canonical-workspace-path> \
  --reference <local-reference-id> \
  --observed-at <canonical-RFC3339-UTC> \
  [--previous-snapshot <snapshot.json>]

monika resolve \
  --workspace <dir> \
  --address <region-address.json> \
  --observed-at <canonical-RFC3339-UTC>
```

`--workspace` and `--observed-at` are required. Exactly one target mode is
selected: `--address`, or the `--observation` and `--reference` pair. The
standalone RegionAddress is strict UTF-8 JSON, bounded to 1 MiB, and uses
`region-address.schema.json`. Unknown fields and non-normalizable semantic
values are rejected; no compatibility decoder or implicit Interpreter identity
exists.

`--observed-at` must use the canonical second-precision UTC form such as
`2026-07-17T00:00:00Z`. Resolve never reads the wall clock implicitly.
Consequently, identical workspace bytes and identical command arguments produce
an identical snapshot and golden output.

Reference lookup uses the typed Reference index from the fixed source
Observation. A conflict or diagnostic on another scoped ID remains observable
but does not suppress resolution of the selected consistent Reference. A
failure that prevents construction of that Reference remains a diagnostic and
produces no synthetic target.

`--previous-snapshot` reads one standalone, normalized `ResolutionSnapshot` as
strict UTF-8 JSON with a 1 MiB limit. It is valid only for a Tracking Reference,
and its target must equal that Reference's complete RegionAddress. Direct
RegionAddress input, Pinned References, and Floating References reject the
option as invalid input.

Resolve and WorkspaceGraph construction share the exact RegionAddress resolver.
Whole observation is resolved by Core. Every partial selector carries an exact
InterpreterIdentity and is dispatched against the fixed target Observation.
The built-in selectors are bounded text range, emitted Markdown region ID, and
strict JSONL row filter. Selector resolution is independent from finite Region
enumeration, so a selected JSONL row or Extension Region is materialized even
when `interpretObservation` did not enumerate it. A JSONL snapshot records the
entire observation identity, the selected row as display text, and the selected
row's SHA-256 fingerprint. A missing target produces `unresolved-ref`; malformed
or ambiguous execution produces `invalid-selector`.

Fingerprints are schema-named normalized values. The built-in byte and JSONL
selectors use `sha256-fingerprint.schema.json`; an Extension Interpreter may use
another declared fingerprint schema. A fingerprint is not interchangeable with
a ContentIdentity or Resource revision.

Direct resolution validates the RegionAddress expectation, when present.
Pinned Reference resolution requires at least one expectation on the
RegionAddress or Reference and validates every applicable expectation after the
selected Region has been resolved. The supported evidence domains are
ObservationIdentity, ContentIdentity, schema-named Origin revision, and
schema-named Region fingerprint. A mismatch produces `expectation-failed` and
no snapshot.

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

In Reference mode, an explicitly supplied interpreter extension replaces
built-in source inspection. Monika calls `monika.interpretObservation` for the
source and calls `monika.resolveRegion` for the fixed target in a separate
checked session selected by the target's exact InterpreterIdentity. In direct
mode there is no source interpretation; an explicitly supplied interpreter is
available only for exact target dispatch. The manifest identity and selector
schema must match the target address.
The response region is accepted only when its observation observation identity,
selector, interpreter identity, and byte range match the exact target input.
The resulting snapshot records the declarative target address rather than the
resolved Region ID, so repeated resolution is compared by the address and
observed target identity.

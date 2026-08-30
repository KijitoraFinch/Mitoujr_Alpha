# Inline-to-Sidecar Derivation

`monika derive` deterministically materializes explicit Markdown observations
into the Monika-owned portion of a YAML sidecar. It does not infer new
annotations, delete sidecar-only data, or write files directly.

## Sidecar ownership

Sidecar version 2 names its target Origin explicitly and has two ownership
sections:

```yaml
version: 2
scope:
  origin:
    kind: workspace
    path: docs/example.md
authored:
  refs: {}
  annotations: {}
derived:
  refs: {}
  annotations: {}
```

`scope.origin` is the target of the metadata; the filename is only the closed
discovery convention. `derived` is owned by Monika. Derive may replace this complete section with its
canonical block-style rendering. `authored` is owned by the user. Derive never
edits, reformats, or deletes its bytes.

Ownership controls which bytes Derive may edit; it does not define semantic
priority. Equal `authored`, `derived`, and inline values contribute occurrences
to one consistent typed-index entry. Different values with the same scoped ID
form an explicit conflict. Core does not choose the authored, derived, inline,
or first-read value.

The root document and `derived` section use block-style mappings. Empty
`derived.refs` and `derived.annotations` may use `{}`. The parser accepts flow
style inside `authored` because Monika does not edit that region. Anchors,
aliases, explicit tags, duplicate keys, unknown fields, unsafe numeric values,
and unsupported semantic variants remain invalid everywhere.

## Input and eligibility

```sh
monika derive --workspace <dir> --observation <canonical-path> --target sidecar
```

All options are required and occur once. Derive builds one immutable
`WorkspaceGraphSnapshot` and consumes the fixed Observation,
`SidecarSnapshot`, and typed occurrences from that value. It does not re-read
the primary file or Sidecar while constructing a patch.

An inline annotation is eligible when its occurrence is in the selected fixed
Observation and it has a resolved Region subject and Reference object. Required
Reference definitions are selected from occurrences in that same Observation.
The complete canonical `derived` section is a deterministic projection of
those explicit occurrences. Existing Sidecar occurrences remain graph inputs,
but they do not suppress or alter that projection.

## Patch construction

For an existing sidecar, the deriver uses libyaml parser events to locate the
complete `derived` section and converts YAML character positions to UTF-8 byte
offsets. If the section is absent, it inserts one before `authored`. It renders
references and annotations in scoped-ID order, quotes user-controlled strings,
and proposes one edit patch containing:

- the current sidecar content identity;
- the exact resulting content identity;
- a stable patch ID derived from the operation and result;
- one half-open byte edit covering only `derived`;
- `derive:inline-to-sidecar` provenance.

For a missing sidecar, the deriver proposes a create patch. The new document
contains the explicit `scope.origin`, empty `authored` mappings, and canonical
`derived` data. Create patches
carry their complete content and resulting identity, but no expected identity
or text edits.

The patch algebra is a closed `create | edit` sum. An edit cannot carry create
content, and a create cannot carry an expected identity or edit list. Applying
a create patch uses an absent-only atomic publication operation. Existing
different content produces `target-already-exists`; existing identical
result content is a no-op.

## CLI handoff and idempotency

Apply can consume one patch object directly:

```sh
monika apply --workspace <dir> --patch <patch.json>
```

It can also consume a derive command result. A result with one patch is selected
automatically; a result with multiple patches requires `--patch-id`:

```sh
monika apply --workspace <dir> --result <derive-result.json>
monika apply --workspace <dir> --result <derive-result.json> \
  --patch-id <patch-id>
```

Goldens cover both existing-sidecar edit and missing-sidecar create results.
Integration tests execute `derive -> apply -> derive`; the second derive emits
no patch. Tests also verify that authored bytes remain exact across an edit.

# Inline-to-Sidecar Derivation

`monika derive` deterministically materializes explicit Markdown observations
into the Monika-owned portion of a YAML sidecar. It does not infer new
annotations, delete sidecar-only data, or write files directly.

## Sidecar ownership

Sidecar version 1 has two declarative sections:

```yaml
version: 1
derived:
  refs: {}
  annotations: {}
authored:
  refs: {}
  annotations: {}
```

`derived` is owned by Monika. Derive may replace this complete section with its
canonical block-style rendering. `authored` is owned by the user. Derive never
edits, reformats, or deletes its bytes.

The effective reference and annotation collections are computed by local ID.
An `authored` record with the same ID replaces the complete `derived` record;
there is no field-level deep merge. A differing replacement is observable as
the informational `authored-override` diagnostic. This priority also applies
when an authored record and an inline observation disagree: inspection retains
the divergence diagnostic but selects the authored record.

The root document and `derived` section use block-style mappings. Empty
`derived.refs` and `derived.annotations` may use `{}`. The parser accepts flow
style inside `authored` because Monika does not edit that region. Anchors,
aliases, explicit tags, duplicate keys, unknown fields, unsafe numeric values,
and unsupported semantic variants remain invalid everywhere.

## Input and eligibility

```sh
monika derive --workspace <dir> --artifact <canonical-path> --target sidecar
```

All options are required and occur once. The artifact is inspected through the
same retained-handle and strict parser boundary as `monika inspect`.

An inline annotation is eligible when it has a Markdown-inline
materialization, has a resolved region subject and reference object, and no
effective sidecar annotation has the same scoped ID. A referenced inline link
is included in `derived.refs` only when no effective sidecar reference already
declares that ID. Existing derived records remain semantically present. This
command does not automatically delete them, although replacing the complete
`derived` section canonicalizes their YAML representation.

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
contains canonical `derived` data and empty `authored` mappings. Create patches
carry their complete content and resulting identity, but no expected identity
or text edits.

The patch algebra is a closed `create | edit` sum. An edit cannot carry create
content, and a create cannot carry an expected identity or edit list. Applying
a create patch uses an absent-only atomic publication operation. Existing
different content produces `artifact-already-exists`; existing identical
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

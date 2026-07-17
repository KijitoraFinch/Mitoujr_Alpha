# Inline-to-Sidecar Derivation

The first executable `monika derive` slice deterministically materializes an
explicit inline Markdown annotation into an existing sidecar. It does not infer
new annotations and does not write files directly.

## Input and Eligibility

```sh
monika derive --workspace <dir> --artifact <canonical-path> --target sidecar
```

All options are required and occur once. The artifact is inspected through the
same retained-handle and strict parser boundary as `monika inspect`. An
annotation is eligible when it has a Markdown-inline materialization, has no
sidecar materialization with the same scoped ID, has a resolved region subject,
and has a reference object.

If inline and sidecar records with the same scoped ID have equal subject,
predicate, and object, inspection merges their provenance and materialization
surfaces. If they disagree, inspection emits `divergent` and derivation does not
propose a patch.

## Patch Construction

The deriver locates the `annotations` mapping through libyaml parser events and
converts YAML character positions back to UTF-8 byte offsets. It does not search
for indentation with a regular expression. Entries are ordered by scoped ID and
rendered with double-quoted user values. The patch is one insertion before the
mapping-end event and contains:

- the sidecar's current content identity;
- the exact resulting content identity;
- a stable patch ID derived from the replacement bytes;
- a half-open byte insertion range;
- `derive:inline-to-sidecar` provenance.

The editable v1 surface currently requires an existing sidecar whose
`annotations` value is a block-style mapping. Flow-style mappings remain valid
read inputs, but derive returns an `invalid-sidecar` diagnostic instead of
rewriting the whole file and potentially discarding user layout or comments.
Create-file patches are outside the current patch algebra, so a missing sidecar
is likewise reported rather than written directly.

The CLI golden executes `derive -> apply -> derive` in a temporary workspace.
The first derive proposes one patch, apply succeeds through the core filesystem
boundary, and the second derive returns no patch. This fixes derivation
idempotency as an observable contract.

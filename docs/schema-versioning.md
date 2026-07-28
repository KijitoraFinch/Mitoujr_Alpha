# Schema Versioning

`schemaVersion` identifies an observable JSON contract, not a development
phase. Command results currently use the decimal string `"5"`.

Version 1 fixed a closed command-result object before artifact observations
were added. Version 2 adds `artifacts` as a required collection. Because version
1 has `additionalProperties: false`, even an optional new top-level field would
be rejected by a conforming version 1 consumer; the change therefore requires a
new version.

Version 3 adds required `regions`, `references`, and `annotations` observation
collections. It also replaces diagnostic location region and annotation strings
with explicit artifact-local scoped ID objects. Version 2 is closed, so these
additions and the location-shape change cannot be emitted under version 2.

Version 4 adds the required `capabilities` observation collection and the
closed `CapabilityDescriptor` definition. All commands emit the collection,
including an empty array when they do not report capabilities. Because version
3 is also closed, the new top-level field requires a new version.

Version 5 changes `ProposedPatch` into a closed `create | edit` sum. It also
allows a changed artifact from creation to omit `before`, and adds the
`artifact-already-exists` conflict and `authored-override` diagnostic code.
These changes alter closed nested objects, so they cannot be emitted as version
4 documents.

A version must change when an existing conforming consumer could reject a new
document, misinterpret it, or accept a document whose meaning changed. This
includes adding fields to closed objects, changing required fields, changing
normalization or path rules, tightening accepted values, and changing the
relationship between `status`, payloads, diagnostics, and `exitClass`.

Encoders, JSON Schema, standalone wrapper schemas, golden files, transition
fixtures, and cross-implementation tests change together. A command does not
silently emit a new shape under an old version. Historical schemas must be
retained once an externally released version needs continued validation; until
then, Git history records the unreleased version 1 contract.

The patch input used by the current single-patch `apply` slice has no outer
versioned envelope. Adding a patch-set envelope is a separate contract decision
and must not reuse the command-result version implicitly.

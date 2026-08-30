# Schema Versioning

`schemaVersion` identifies one observable JSON contract. Command results
currently use the decimal string `"9"`.

Version 9 makes an Observation's host-owned representation explicit. Every
Observation has either a byte representation or a schema-named normalized
structured value. Extension origins also carry an exact Resource Observer
name/version identity and a normalized locator value.

Version 8 adds structured `extensionFailure` details to diagnostics. The core
diagnostic code and severity remain closed, while the method operation,
extension-specific failure code, and normalized protocol data remain available
without parsing a rendered message.

Version 7 exposes `Observation` directly as `id`, `origin`, and a
type-qualified `identity`. `contentIdentity` is optional adapter data for an
observation backed by one byte string. Scoped IDs name their observation,
`RegionAddress` contains `origin`, selectors use `whole-observation`, and
filesystem effects are reported in `changedFiles`.

Monika has not released an extension ecosystem or persistent protocol data.
The implementation therefore accepts only the current shape and contains no
legacy decoder, field alias, or implicit conversion for earlier development
drafts. Git history records those drafts.

A version changes whenever an existing consumer could reject a new document,
misinterpret it, or accept a document whose meaning changed. This includes
changes to closed objects, required fields, normalization and path rules,
accepted values, and the relationship between `status`, payloads,
diagnostics, and `exitClass`.

Encoders, JSON Schema, standalone schemas, golden files, transition fixtures,
extension protocol fixtures, and cross-implementation tests change together.
A command never emits a new shape under an old version. Historical schemas are
retained only after a released contract requires continued validation.

The current single-patch `apply` input has no outer versioned envelope. Adding
a patch-set envelope is a separate contract decision and must not reuse the
command-result version implicitly.

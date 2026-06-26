# Schema Notes

`schemas/command-result.schema.json` defines the Phase 1 observable result and
its reusable diagnostic, patch, snapshot, path, range, identity, and conflict
definitions. The individual diagnostic, patch, and snapshot schemas reference
those definitions so that their contracts cannot drift through duplication.

The schema version is the string `"1"`. Required collections are never omitted.
Optional values are represented by field omission unless a field explicitly
defines another meaning. Phase 1 schemas do not admit `null`.

The OCaml representative fixture is encoded by `Normal_json` and validated
against the schema by `tools/check_golden.py`. The checker also mutates boundary
cases to ensure missing collections, `null`, and empty patch edit lists are
rejected. Its snapshot contains the same `row-filter.where` shape used by the
basic sidecar fixture, so the encoder and selector schema are checked together.

Conflict schema definitions mirror the OCaml algebraic data type with `oneOf`.
Each conflict kind has its own required detail fields and rejects fields from
other variants.

The command-result schema also constrains `status` and payload collections
together. For example, `ok` cannot carry patches, changed artifacts, or
conflicts; `applied` requires changed artifacts and rejects patches and
conflicts; `conflict` requires conflicts and rejects patches and changed
artifacts.

Path strings follow `Workspace_path.to_canonical_string`, not a looser
percent-escaped path syntax. Percent escapes use uppercase hex and are only used
for bytes that are not unreserved path characters. Encoded slash, NUL, encoded
unreserved characters, lowercase escapes, empty segments, and literal dot or
dot-dot segments are rejected.

`row-filter.where` is the observable projection of the OCaml
`Selector.Row_filter` abstract map. It is a non-empty JSON object with non-empty
property names and exact string, integer, or boolean literals. Floating-point
numbers and `null` are not part of the current semantic model. Object keys are
emitted in canonical lexical order. The selected interpreter owns the meaning
of applying those conditions to an artifact.

Artifact, region, reference, annotation, and capability files remain Phase 0
scaffolds until their command-level observable forms are implemented.
The semantic `Reference` model is nevertheless typed: its expectations use the
closed `Expectation` algebra and validated `Content_digest` values rather than
unstructured strings.

The first JSON input decoder is for `ProposedPatch` values consumed by
`monika apply`. It should accept the same patch object shape that `Normal_json`
emits inside command results, but it is not part of `Normal_json`: output
encoding and input validation have different responsibilities. The decoder must
be strict about required fields, unknown fields, `null`, and type mismatches,
and it must construct semantic values through the same constructors used by the
OCaml model tests.

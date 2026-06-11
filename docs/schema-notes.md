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

`row-filter.where` is a non-empty JSON object with non-empty property names and
string values. Object keys are emitted in canonical lexical order. The schema
describes the observable selector structure; the selected interpreter owns the
meaning of applying those conditions to an artifact.

Artifact, region, reference, annotation, and capability files remain Phase 0
scaffolds until their command-level observable forms are implemented.
The semantic `Reference` model is nevertheless typed: its expectations use the
closed `Expectation` algebra rather than unstructured strings.

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
rejected.

Artifact, region, reference, annotation, and capability files remain Phase 0
scaffolds until their command-level observable forms are implemented.

# Bootstrap Log 0001

## 2026-06-11

### Done

- Corrected wording errors in the top-level guidance and plan.
- Added the Phase 0 directory structure.
- Added minimal OCaml and Rust scaffolds.
- Added scaffold JSON schemas, golden-output locations, fixtures, diagnostics,
  protocol notes, and local validation.

### Observations

- The repository currently uses scaffold schemas. They are valid JSON Schema
  files, but they do not yet define the final field-level contracts.
- The first fixture records intended cases before implementation behavior exists.

### Open Items

- Fix concrete selector semantics in Phase 1.
- Fix patch format and conflict semantics in Phase 1.
- Decide how OCaml will generate or validate JSON Schema in Phase 1.
- Decide the Rust comparison harness after the first golden outputs exist.

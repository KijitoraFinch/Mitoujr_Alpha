# Schema Notes

The `schemas/` directory contains valid JSON Schema scaffold files for Phase 0.
They intentionally require only `schemaVersion` and allow additional properties.

Phase 1 must replace scaffold permissiveness with field-level contracts for:

- artifact descriptors
- region descriptors
- references
- annotations
- diagnostics
- proposed patches
- capabilities
- resolution snapshots

Schema changes must preserve an explicit compatibility rule.

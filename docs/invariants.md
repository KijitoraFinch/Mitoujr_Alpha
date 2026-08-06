# Invariants

These invariants apply before concrete model fields are detailed.

- Configuration files do not contain procedures.
- Extensions do not directly write workspace files.
- Writes are represented as patches before they are applied.
- `derive` is deterministic for the same normalized input.
- `infer` is separate from `derive` and is not part of the initial core.
- Diagnostics use stable codes.
- Generated caches are not primary sources of truth.
- Source artifacts and annotation artifacts are primary inputs.
- An observation identity includes its observation type.
- A region belongs to exactly one fixed observation.
- Region resolution is determined by interpreter name and version, observation
  identity, and selector.
- An unresolved selector is not silently moved to a similar region.
- Extension contracts are language-neutral values and operations, not internal
  reference-implementation types.
- CLI output must be machine-readable and stable after the schema is fixed.

# Invariants

These invariants apply before concrete model fields are detailed.

- Configuration files do not contain procedures.
- Extensions do not directly write workspace files.
- Writes are represented as patches before they are applied.
- `derive` is deterministic for the same normalized input.
- `infer` is separate from `derive` and is not part of the initial core.
- Diagnostics use stable codes.
- Generated caches are not primary sources of truth.
- Primary Resource observations and Sidecar metadata snapshots are independent
  inputs; a Sidecar snapshot is not an observation.
- Sidecar metadata is excluded from Resource inventory, interpreter dispatch,
  and observation coverage.
- A reserved Sidecar that cannot be read or decoded is an explicit metadata
  failure; it does not fall back to an unknown primary Resource.
- An observation identity includes its observation type.
- A region belongs to exactly one fixed observation.
- An observation's type and identity are fixed before interpreter selection;
  interpretation consumes that same observation without reclassification.
- An interpretation contains regions, references, and annotations for its input
  observation, never newly produced observations.
- Region resolution is determined by interpreter name and version, observation
  identity, and selector.
- An interpreter name and version occur as one identity: both fields are present
  or both are absent, and no implicit version is supplied.
- An unresolved selector is not silently moved to a similar region.
- Interpreter candidate dispatch has no implicit priority: zero candidates are
  unsupported, and multiple applicable candidates are an explicit failure.
- Failures crossing a command or extension-session boundary are explicit values;
  an implementation exception is not a substitute for a result.
- Extension contracts are language-neutral values and operations, not internal
  reference-implementation types.
- CLI output must be machine-readable and stable after the schema is fixed.

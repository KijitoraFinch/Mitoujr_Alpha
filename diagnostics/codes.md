# Diagnostic Codes

This registry is the Phase 0 starting point. Phase 1 must fix exact payload
requirements, severity policy, and examples for each code.

| Code | Default Severity | Meaning |
| --- | --- | --- |
| `sidecar-only` | info | Annotation exists only in a sidecar representation. |
| `inline-only` | warning | Annotation exists only in an inline representation. |
| `divergent` | error | Two explicit representations disagree after normalization. |
| `stale-selector` | error | A selector no longer resolves to the expected region. |
| `duplicate` | warning | A record is duplicated under the same normalization rule. |
| `unreferenced-ref` | warning | A reference is declared but not used. |
| `unresolved-ref` | error | A reference cannot be resolved. |
| `expectation-failed` | error | A resolved target does not satisfy an expectation. |
| `invalid-sidecar` | error | A sidecar file is syntactically or structurally invalid. |
| `invalid-selector` | error | A selector is not valid for its interpreter. |
| `unsupported-artifact` | warning | No capability can inspect an artifact. |

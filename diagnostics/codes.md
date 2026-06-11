# Diagnostic Codes

This registry defines the closed Phase 1 diagnostic code set.

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

Each normalized diagnostic contains:

- `code`
- `defaultSeverity`, taken from this registry
- `effectiveSeverity`, after policy application
- a non-empty `message`
- optional `location`
- `suggestedFixes`, always represented as an array

Policy changes only `effectiveSeverity`; it does not rewrite the registry
default. A command has exit class `diagnostic-error` when at least one effective
severity is `error`, or when patch application conflicts.

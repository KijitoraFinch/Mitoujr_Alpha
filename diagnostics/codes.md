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
| `resolution-changed` | warning | A Tracking reference resolves to a different Observation identity or Region fingerprint than its previous snapshot. |
| `invalid-sidecar` | error | A sidecar file is syntactically or structurally invalid. |
| `invalid-selector` | error | A selector is not valid for its interpreter. |
| `unsupported-observation` | warning | No capability can inspect an observation. |
| `unsupported-filesystem-entry` | warning | Scan encountered a symbolic link or another entry kind outside the current traversal policy. |
| `observation-failure` | error | A primary Resource could not be fixed as an Observation. |
| `metadata-failure` | error | Sidecar metadata could not be fixed or decoded. |
| `extension-failure` | error | An extension session or method failed without a more specific core diagnostic classification. |

Each normalized diagnostic contains:

- `code`
- `defaultSeverity`, taken from this registry
- `effectiveSeverity`, after policy application
- a non-empty `message`
- optional `location`
- optional `extensionFailure`, containing the operation, extension-specific code,
  and normalized protocol data without rewriting them into a message
- `suggestedFixes`, always represented as an array

The `extension-failure` diagnostic code requires `extensionFailure`. The same
details may accompany `unsupported-observation`, `unresolved-ref`, or
`invalid-selector` when an Extension failure has a more specific core
classification.

Policy changes only `effectiveSeverity`; it does not rewrite the registry
default. A command has exit class `diagnostic-error` when at least one effective
severity is `error`, or when patch application conflicts.

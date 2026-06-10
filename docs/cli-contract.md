# CLI Contract Notes

The initial CLI family is:

- `monika scan`
- `monika inspect`
- `monika resolve`
- `monika check`
- `monika derive`
- `monika apply`
- `monika capabilities`
- `monika extension test`

Phase 0 does not finalize command output. Phase 1 must define:

- JSON output envelope
- schema version placement
- exit code mapping
- path normalization
- diagnostic ordering
- stable sorting rules
- handling of environment-dependent values

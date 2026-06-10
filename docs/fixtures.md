# Fixtures

The first fixture corpus is `fixtures/basic/`.

It is intentionally small but records the important cases that later phases must
make executable:

- Markdown inline link
- sidecar-only annotation
- inline-only annotation
- divergent annotation
- stale selector
- unreferenced reference
- unresolved reference
- source comment annotation
- JSONL pinned reference

Phase 0 validates that the fixture corpus exists and declares these cases. Later
phases must bind each case to concrete expected diagnostics and patches.

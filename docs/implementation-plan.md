# Implementation Plan

The top-level plan is kept in [PLAN_GLOBAL.md](../PLAN_GLOBAL.md). This file is
the concise implementation entry point for Phase 0.

## Phase 0 Deliverables

- `sugar/`: OCaml reference implementation scaffold.
- `bitter/`: Rust high-speed implementation scaffold.
- `schemas/`: valid JSON Schema scaffold files.
- `golden/`: golden-output locations for each CLI family.
- `fixtures/basic/`: the first fixture corpus and case inventory.
- `docs/`: bootstrap documentation.
- `protocol/`: extension protocol notes.
- `diagnostics/`: diagnostic code registry.
- `tools/check_phase0.py`: local Phase 0 verifier.
- `tools/check_golden.py`: scaffold golden-output verifier.
- `.github/workflows/phase0.yml`: minimum CI entry point.

## Next Phase Gate

Phase 1 starts only after Phase 0 checks pass. Phase 1 fixes concrete JSON
schemas, diagnostic code details, selector families, path normalization, and CLI
output envelopes.

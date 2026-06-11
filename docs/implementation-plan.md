# Implementation Plan

The top-level plan is kept in [PLAN_GLOBAL.md](../PLAN_GLOBAL.md). This file
records the completed bootstrap and current Phase 1 boundary.

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

## Phase 1 Status

Sugar now provides the semantic model, command result normal form, concrete
diagnostic/patch/snapshot schema definitions, pure workspace snapshots, and
deterministic text-patch application. Normal-form and workspace-transition
goldens are generated from the OCaml implementation.

Production CLI behavior, selector resolution, filesystem writes, create/delete
patches, and Bitter parity remain later work.

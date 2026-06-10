# Overview

Monika treats workspace files, source code, logs, experimental data, web
captures, and unknown blobs as artifacts that can be inspected, related, checked,
and updated through patches.

The first implementation target is not a thin prototype. The repository starts
with a reference implementation in OCaml, a later high-speed implementation in
Rust, and a specification layer that both implementations must satisfy.

## Current Phase

This repository is in Phase 0. The goal of this phase is to establish the
development foundation before the model is detailed:

- stable directories for implementations, schemas, fixtures, golden outputs,
  diagnostics, protocol notes, and documentation
- runnable local checks for Phase 0 structure
- buildable OCaml and Rust scaffolds with no domain behavior
- explicit fixture and golden-output locations for later implementation work

Field-level schemas, selector semantics, and patch semantics are intentionally
left for Phase 1 and later phases.

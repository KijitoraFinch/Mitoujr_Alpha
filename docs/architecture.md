# Architecture

The core model is described in [DESIGN.md](../DESIGN.md). This document records
the Phase 0 architecture boundary.

## Core Concepts

- Artifact: a unit that contains information, such as Markdown, source code,
  JSONL, logs, web captures, PDFs, or blobs.
- Region: a selectable part of an artifact.
- Reference: a value that targets an artifact or region.
- Annotation: information attached to a region.
- Relation: a semantic relationship between regions, references, or values.
- Snapshot: the observed result of resolving a reference at a point in time.
- Diagnostic: a stable report about inconsistency or invalid state.
- Patch: an edit proposal that can be applied only through core commands.
- Capability: an extension-provided operation with a narrow contract.

## Phase 1 Boundary

Sugar owns the semantic model and maps it to a separately typed observable
normal form. Only the normal form is encoded as JSON. This prevents JSON
representation choices from leaking into interpretation and workspace logic.

Phase 1 fixes:

- workspace-relative logical path normalization
- SHA-256 content identity
- byte-offset text ranges and edits
- the initial selector algebra
- diagnostic severity and command result derivation
- stable normal-form ordering
- pure workspace snapshot and patch application behavior

Filesystem traversal, symlink policy, atomic writes, selector resolution, and the
production CLI remain outside this boundary.

`ProposedPatch` carries both the expected input identity and resulting content
identity. The latter is necessary to recognize a repeated application as a
no-op without retaining hidden mutable state or reconstructing replaced bytes.

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

## Phase 0 Boundary

Phase 0 creates infrastructure only. It does not define final selector formats,
canonical graph normalization, extension process behavior, or patch conflict
semantics. Those details must be fixed in the specification layer before domain
behavior is implemented.

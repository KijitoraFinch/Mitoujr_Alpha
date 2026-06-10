# Design Decisions

## D-0001: No Procedures In Configuration

Date: 2026-06-11

### Decision

YAML and JSON sidecar files must not contain pipelines, steps, conditional
execution, or command execution.

### Rationale

Procedural configuration would turn the system into a workflow engine and would
make compatibility, security, debugging, and idempotency harder to reason about.

### Consequences

Configuration files may contain values such as references, selectors, bindings,
expectations, relations, policy, and schema versions. Core code and extensions
own behavior.

## D-0002: Writes Go Through Patches

Date: 2026-06-11

### Decision

Helpers and extensions return proposed patches. They do not directly modify
workspace files.

### Rationale

Patch-based writes make review, idempotency, conflict detection, and provenance
possible across multiple artifact types.

### Consequences

The core `apply` command is the only component that performs workspace writes.
Patch format and conflict semantics must be fixed before write behavior is
implemented.

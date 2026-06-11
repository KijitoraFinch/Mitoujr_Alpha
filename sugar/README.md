# Sugar

Sugar is the OCaml reference implementation. Phase 1 defines the semantic model,
observable normal form, JSON encoder, and pure workspace transition behavior.

The library is intentionally layered:

```text
semantic model -> Normal -> Normal_json
workspace snapshot + proposed patch -> Workspace_ops -> workspace snapshot
```

Semantic modules do not depend on Yojson. Filesystem traversal and writes remain
outside the Phase 1 boundary.

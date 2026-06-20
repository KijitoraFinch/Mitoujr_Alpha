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

The OCaml semantic model is the source of truth. Sugar core represents row
filters as non-empty abstract maps from validated field names to typed literals;
the interpreter named by a target owns their resolution semantics. Reference
expectations use the closed `Expectation` algebra and validated content digests.
Normal forms, encoders, schemas, and goldens are derived only after those
semantic types and invariant tests are established.

Artifact origins, reference targets, and command results are also protected by
constructors. Empty schema-visible strings are rejected before normalization,
and command-result effects determine which payload collections may be non-empty.

# Inspect Interpreter Boundary

This document fixes the first executable `monika inspect` slice. Inspection
extracts explicit information; it does not resolve selectors, audit
inconsistencies, derive edits, or infer unstated relations.

## Input and Filesystem Boundary

The command accepts one native workspace root and one canonical
workspace-relative artifact path. The selected artifact and its optional
sidecar are opened by component through retained directory handles. Exact
native spelling is required, and symbolic links and Windows reparse points
below the resolved workspace root are not followed.

Content is read from the retained file handle. Identity, size, modification
time, and change time are compared before and after EOF. One detected mutation
is retried; a second mutation produces a stable internal failure. Inspection
therefore never parses bytes that were already classified as an unstable read.

## Markdown Surface

The standard Markdown interpreter uses a CommonMark parser with source
locations enabled. It recognizes these whole HTML comment directives:

```text
<!-- monika:region id=<local-id> -->
<!-- monika:annotation id=<local-id> predicate=<predicate> ref=<reference-id> -->
```

Attributes are unquoted, non-empty `key=value` tokens. Duplicate, missing, and
unknown attributes are errors. A region directive selects the next CommonMark
paragraph, provided no other Monika directive occurs first. Its selector and
range are the paragraph's half-open UTF-8 byte range. Its summary is CommonMark
plain text, while its fingerprint is the SHA-256 digest of the exact selected
bytes and is independent of the paragraph's earlier file offset.

An annotation directive attaches to the nearest preceding declared region. A
CommonMark link with a non-empty URI fragment declares or uses a reference whose
local ID is that decoded fragment. Relative link paths are normalized against
the inspected artifact and must remain inside the workspace. Link parsing,
escaping, reference-link lookup, and byte ranges come from the CommonMark AST,
not from a second ad-hoc Markdown grammar.

## Sidecar v1 Surface

For `docs/name.md`, the optional sidecar is
`docs/name.annotations.yaml`. Sidecar v1 accepts only the declarative `version`,
`refs`, and `annotations` structure shown in [DESIGN.md](../DESIGN.md). It
rejects duplicate keys, aliases, anchors, explicit YAML tags, unknown fields,
nulls, floating-point selector literals, invalid UTF-8, unsafe integers, and
unsupported origin or selector variants. This deliberately avoids YAML-native
object construction and expansion behavior.

Observation IDs are scoped to the primary artifact. The sidecar file is still
emitted as a separate artifact and recorded as the annotation's materialization
surface. When an inline link fragment and a sidecar reference have the same
scoped ID, the sidecar supplies the reference selector, binding, and
expectations, while the inline link adds provenance. Their target artifacts
must agree; disagreement is a `divergent` diagnostic. This permits an inline
`path#reference-id` use to name a richer sidecar row-filter selector without
discarding either explicit surface.

## Observable Contract

The result uses command-result schema version `"4"` and includes the primary
artifact, an existing sidecar artifact, and normalized `regions`, `references`,
and `annotations`. The executable golden for `fixtures/basic` checks stdout,
process exit status, JSON Schema, semantic constraints, identities, ranges,
provenance, and canonical ordering.

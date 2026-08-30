# Inspect Interpreter Boundary

This document fixes the first executable `monika inspect` slice. Inspection
extracts explicit information; it does not resolve selectors, audit
inconsistencies, derive edits, or infer unstated relations.

## Input and Filesystem Boundary

The command accepts one native workspace root and one canonical
workspace-relative observation path. The selected observation and its optional
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
the inspected observation and must remain inside the workspace. Link parsing,
escaping, reference-link lookup, and byte ranges come from the CommonMark AST,
not from a second ad-hoc Markdown grammar.

Multiple links with the same local reference ID and target produce one
`Reference` declaration whose provenance retains every link range. If the same
local reference ID is used for different targets, inspection reports an
`invalid-selector` diagnostic instead of emitting ambiguous declarations.

Every successfully parsed link also produces a query-layer
`ReferenceOccurrence`. A workspace-relative link without a fragment targets the
whole observation directly. A fragment-bearing occurrence uses its named
`ReferenceId`, allowing a sidecar declaration to supply a richer selector.
HTTP(S) and other URI schemes are retained as direct web or external targets.
The containing declared region is used as the source when its byte range
contains the link; otherwise the source is the whole Markdown observation. These
occurrences are exposed by the Agent query layer and do not add fields to the
version 8 command-result envelope.

## Sidecar v1 Surface

For `docs/name.md`, the optional sidecar is
`docs/name.annotations.yaml`. Sidecar v1 accepts only the declarative
`version`, `derived`, and `authored` structure shown in
[DESIGN.md](../DESIGN.md). Each ownership section may contain `refs` and
`annotations`. It rejects duplicate keys, aliases, anchors, explicit YAML tags,
unknown fields, nulls, floating-point selector literals, invalid UTF-8, unsafe
integers, and unsupported origin or selector variants. This deliberately
avoids YAML-native object construction and expansion behavior.
An address either omits both interpreter fields or supplies both `interpreter`
and `interpreterVersion`; the decoder never assumes a version.

The root and `derived` section use a canonical block-style layout, with `{}` as
the only accepted flow form for an empty derived mapping. `authored` may use
flow style because Monika does not edit that region. A duplicate local ID is
resolved as a complete-record replacement by `authored`; fields are not deeply
merged. A differing derived record remains observable through
`authored-override`.

Observation IDs are scoped to the primary observation. The sidecar file is still
emitted as a separate observation and recorded as the annotation's materialization
surface. When an inline link fragment and a sidecar reference have the same
scoped ID, the sidecar supplies the reference selector, binding, and
expectations, while the inline link adds provenance. Their target observations
must agree; disagreement is a `divergent` diagnostic. This permits an inline
`path#reference-id` use to name a richer sidecar row-filter selector without
discarding either explicit surface.

## Observable Contract

The result uses command-result schema version `"8"` and includes the primary
observation, an existing sidecar observation, and normalized `regions`, `references`,
and `annotations`. The executable golden for `fixtures/basic` checks stdout,
process exit status, JSON Schema, semantic constraints, identities, ranges,
provenance, and canonical ordering.

# Agent Query API

This document defines the Agent-facing read-only query boundary. It is separate
from the normalized `CommandResult` protocol used by `scan`, `inspect`,
`resolve`, `check`, `derive`, and `apply`.

The query boundary exists so that an Agent can ask one workspace-level question
without receiving every intermediate observation as a full command-result
envelope. JSON remains available when exact field selection or shell processing
is useful.

## Design Goals

- Express the Agent's task directly instead of requiring a
  `scan -> inspect each artifact -> resolve each reference` subprocess loop.
- Preserve the normalized command-result JSON as the implementation parity,
  schema, and golden-test boundary.
- Keep reference declarations, actual reference occurrences, and semantic
  relations distinct.
- Return only explicit observations. Querying does not infer an unstated
  relation.
- State observation coverage explicitly. An empty match set must not imply that
  unsupported artifacts contain no relations.
- Derive query results from an immutable workspace observation. A cache may
  accelerate construction, but it must not change the result.

## Observation Model

### Reference

A `Reference` is a named declaration of a target address. It owns binding,
expectation, and target semantics. A sidecar can declare a reference without any
current use, so a declaration alone is not a graph edge.

### ReferenceOccurrence

A `ReferenceOccurrence` records an actual syntactic use.

```text
ReferenceOccurrence
  source artifact
  optional containing region
  source byte range
  target:
    named ReferenceId
    or direct RegionAddress
```

A Markdown link with a non-empty fragment uses the fragment as the existing
artifact-local `ReferenceId`. A workspace-relative Markdown link without a
fragment is a direct occurrence targeting the whole artifact. The source is the
smallest declared region containing the link, or the whole source artifact when
no declared region contains it. Repeated uses of one named reference remain
distinct occurrences even though the interpreter emits only one declaration
for that `ReferenceId` and target.

Occurrence identity is the tuple of source artifact and source byte range within
one immutable workspace observation. It is intentionally not a persistent
semantic identifier.

### Relation

A `Relation` is an explicit predicate-bearing edge, such as `supported-by` or
`contradicts`. The initial standard projection derives relations
deterministically from annotations whose object is a region or reference.
Literal-valued annotations are not graph edges.

Reference occurrences use the reserved display predicate `references`; this
does not turn them into semantic `Relation` values.

### WorkspaceGraphSnapshot

`WorkspaceGraphSnapshot` is an immutable value derived from one workspace scan
and the supported interpreters:

```text
artifacts
regions
references
reference occurrences
relations
diagnostics
coverage
```

The graph keeps direction per edge. Two opposite edges are not collapsed into a
`bidirectional` edge because predicates may be asymmetric.

The initial implementation constructs the snapshot for each query. A future
content-addressed cache may be added only if validity includes all artifact
content identities and capability versions. Stale cache entries must never be
returned.

Construction compares every interpreted artifact with the opening inventory
and repeats the workspace scan after all interpretations. If identities or the
artifact set changed, the whole construction is retried once. A second change
fails the query as an unstable workspace rather than mixing observations from
different states.

## `monika related`

```sh
monika related --workspace <dir> --artifact <canonical-workspace-path>
monika related --workspace <dir> --artifact <path> \
  --direction incoming|outgoing|both
monika related --workspace <dir> --artifact <path> \
  --predicate <predicate> --limit <positive-integer>
monika related --workspace <dir> --artifact <path> --json
```

`--workspace` and `--artifact` are required and occur at most once. Direction
defaults to `both`; limit defaults to 50. `--predicate` filters exact,
case-sensitive predicate values. `--json` selects the query-specific JSON
result instead of the Agent-readable text renderer.

An edge is:

- `outgoing` when only its source belongs to the selected artifact;
- `incoming` when only its target belongs to the selected artifact;
- `internal` when both endpoints belong to the selected artifact.

`both` includes all three classes. `incoming` and `outgoing` also include
`internal`, because an internal edge satisfies both endpoint conditions.

Named reference targets are resolved using the current workspace observation.
Source and target endpoint resolution are reported separately. Each endpoint
distinguishes:

- `resolved`;
- `unresolved`;
- `invalid-selector`;
- `unreadable`;
- `not-checked` for a target origin unsupported by the current resolver.

Artifact-level incoming matches use the declared target artifact even when its
selector is unresolved. This makes a broken incoming reference discoverable.

## `monika read`

```sh
monika read --workspace <dir> --artifact <canonical-workspace-path>
```

`read` renders one supported artifact for direct Agent reading. It uses one
stable retained-handle observation and returns:

- the artifact media type and content identity;
- declared regions and summaries;
- named references and targets;
- explicit annotations;
- the exact artifact content.

`read` is not another JSON protocol. An Agent that needs the full normalized
observation uses `monika inspect` instead. Interpreter or sidecar diagnostics
fail the read rather than returning a body whose associated observations may be
incomplete.

## Text Result

The text renderer is intended for direct Agent and human reading. It shows the
selected artifact, outgoing and incoming sections, edge kind, predicate,
endpoints, selector, resolution state, truncation, and coverage. Empty sections
are omitted.

If no edge matches, the renderer says that no explicit relation was observed
within the stated coverage. It must not claim that no relation exists when
coverage is incomplete.

## JSON Result

The JSON form has its own schema version and does not use the generic
`CommandResult` envelope:

```json
{
  "schemaVersion": "1",
  "query": {
    "artifact": "docs/linking.md",
    "direction": "both",
    "limit": 50
  },
  "matches": [],
  "coverage": {
    "scannedArtifacts": 5,
    "interpretedArtifacts": 2,
    "unsupportedArtifacts": 3,
    "failedArtifacts": 0,
    "complete": false
  },
  "truncated": false
}
```

Matches are sorted by direction, predicate, source, target, edge kind, and
evidence identifiers before the limit is applied. `truncated` is true exactly
when additional sorted matches exist.

## Failure and Completeness

Usage failures exit 2. Filesystem or interpreter failures that prevent a stable
workspace observation exit 3. A successfully constructed but incomplete graph
still exits 0 and reports its coverage. Unsupported artifacts count toward
incomplete coverage; they are not fabricated as failures.

Diagnostics found while interpreting a supported artifact make that artifact a
failed observation for graph purposes. Its partial edges are not returned.
This prevents malformed sidecars or selectors from looking like a valid empty
result.

## Agent Usage

The ordinary traversal is:

```text
related -> select relevant neighbors -> read selected artifacts
```

The Agent uses `--json` only when it needs exact filtering, bulk selection, or
stable field access. The full normalized `inspect` JSON remains available for
protocol-level evidence and editing workflows.

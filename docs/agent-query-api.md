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
  `scan -> inspect each observation -> resolve each reference` subprocess loop.
- Preserve the normalized command-result JSON as the implementation parity,
  schema, and golden-test boundary.
- Keep reference declarations, actual reference occurrences, and semantic
  relations distinct.
- Return only explicit observations. Querying does not infer an unstated
  relation.
- State observation coverage explicitly. An empty match set must not imply that
  unsupported observations contain no relations.
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
  source observation
  optional containing region
  source byte range
  target:
    named ReferenceId
    or direct RegionAddress
```

A Markdown link with a non-empty fragment uses the fragment as the existing
observation-scoped `ReferenceId`. A workspace-relative Markdown link without a
fragment is a direct occurrence targeting the whole observation. The source is the
smallest declared region containing the link, or the whole source observation when
no declared region contains it. Repeated uses of one named reference remain
distinct occurrences even though the interpreter emits only one declaration
for that `ReferenceId` and target.

Occurrence identity is the tuple of source observation and source byte range within
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
observations
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
content-addressed cache may be added only if validity includes all observation
content identities and capability versions. Stale cache entries must never be
returned.

Construction compares every interpreted observation with the opening inventory
and repeats the workspace scan after all interpretations. If identities or the
observation set changed, the whole construction is retried once. A second change
fails the query as an unstable workspace rather than mixing observations from
different states.

## `monika related`

```sh
monika related --workspace <dir> --observation <canonical-workspace-path>
monika related --workspace <dir> --observation <path> \
  --direction incoming|outgoing|both
monika related --workspace <dir> --observation <path> \
  --predicate <predicate> --limit <positive-integer>
monika related --workspace <dir> --observation <path> --json
monika related --workspace <dir> --observation <path> \
  --region <local-region-id> [--region-scope exact|contained]
monika related --workspace <dir> --observation <path> \
  --extension-registry <file>
monika related --workspace <dir> --observation <path> \
  --extension-manifest <file> --extension-executable <file> \
  [--extension-argument <value>]...
```

`--workspace` and `--observation` are required and occur at most once. Direction
defaults to `both`; limit defaults to 50. `--predicate` filters exact,
case-sensitive predicate values. `--json` selects the query-specific JSON
result instead of the Agent-readable text renderer.

Without `--region`, the selected extent is the whole Observation. With
`--region`, `exact` includes an endpoint only when its extent is `equal` to the
selected Region. `contained` includes `equal` and extents for which the selected
Region `contains` the endpoint. `contained` is the default Region scope.

The explicit extension options create a one-entry registry snapshot for this
query. `--extension-registry` loads multiple installed Interpreters and is
mutually exclusive with those options. Each stable graph-construction attempt
uses an independent checked session per Observation and calls `monika.interpretObservation` only
for paths matching the manifest's applicability, in canonical observation-ID
order. Built-in interpreters remain available for other paths. If a built-in and the extension both apply to one
observation, the query fails as ambiguous instead of choosing a priority or
falling back. An applicable extension failure marks the observation failed and
does not retry it with another interpreter.

If the closing inventory detects a workspace change, the complete graph
construction is retried once with new processes and checked sessions. State from
the rejected attempt is never reused with the new workspace observation.

An edge is:

- `outgoing` when only its source belongs to the selected observation;
- `incoming` when only its target belongs to the selected observation;
- `internal` when both endpoints belong to the selected observation.

`both` includes all three classes. `incoming` and `outgoing` also include
`internal`, because an internal edge satisfies both endpoint conditions.

Region endpoint membership uses the closed relations `equal`, `contains`,
`contained-by`, `overlaps`, and `disjoint`. Core classifies whole-Observation and
built-in Region extents. Installed Interpreters classify their own partial
Regions through `monika.classifyRegionExtents`. A method failure is not treated
as `disjoint`, and Regions from different Observation or Interpreter identities
are not compared.

Named reference targets are resolved using the current workspace observation.
Source and target endpoint resolution are reported separately. Each endpoint
distinguishes:

- `resolved`;
- `unresolved`;
- `invalid-selector`;
- `unreadable`;
- `not-checked` for a target origin unsupported by the current resolver.

Observation-level incoming matches use the declared target observation even when its
selector is unresolved. This makes a broken incoming reference discoverable.

## `monika read`

```sh
monika read --workspace <dir> --observation <canonical-workspace-path>
```

`read` renders one supported observation for direct Agent reading. It uses one
stable retained-handle observation and returns:

- the observation media type and content identity;
- declared regions and summaries;
- named references and targets;
- explicit annotations;
- the exact observation content.

`read` is not another JSON protocol. An Agent that needs the full normalized
observation uses `monika inspect` instead. Interpreter or sidecar diagnostics
fail the read rather than returning a body whose associated observations may be
incomplete.

## Text Result

The text renderer is intended for direct Agent and human reading. It shows the
selected observation, outgoing and incoming sections, edge kind, predicate,
endpoints, selector, resolution state, diagnostics, truncation, and coverage.
Empty sections are omitted. If the query fails before a stable graph is
produced, the renderer states that failure and prints its structured diagnostic
details instead of claiming that no relation was observed.

If no edge matches, the renderer says that no explicit relation was observed
within the stated coverage. It must not claim that no relation exists when
coverage is incomplete.

## JSON Result

The JSON form has its own schema version and does not use the generic
`CommandResult` envelope. Version 4 adds an explicit `status` and a normalized
`diagnostics` collection. It retains the extension origins, schema-named
extension selectors, and evidence fields introduced by earlier versions:

```json
{
  "schemaVersion": "4",
  "status": "incomplete",
  "query": {
    "observation": "docs/linking.md",
    "direction": "both",
    "limit": 50
  },
  "matches": [],
  "diagnostics": [],
  "coverage": {
    "scannedObservations": 5,
    "interpretedObservations": 2,
    "unsupportedObservations": 3,
    "failedObservations": 0,
    "complete": false
  },
  "truncated": false
}
```

Matches are sorted by direction, predicate, source, target, edge kind, and
evidence identifiers before the limit is applied. `truncated` is true exactly
when additional sorted matches exist.

## Failure and Completeness

Usage failures exit 2. Internal filesystem failures that prevent a stable
workspace observation exit 3. A successfully constructed but incomplete graph
has `status: "incomplete"`, still exits 0, and reports its coverage. Unsupported
observations count toward incomplete coverage; they are not fabricated as
failures.

Diagnostics found while interpreting a supported observation make that observation a
failed observation for graph purposes. Its partial edges are not returned, and
the diagnostic is retained in the result. This prevents malformed sidecars or
selectors from looking like a valid empty result.

If an explicitly supplied Extension session cannot start or initialize, the
query returns `status: "failed"`, empty matches, incomplete zero coverage, and
an `extension-failure` diagnostic. Both JSON and text forms are written to
stdout and exit 1. The Extension operation, code, JSON-RPC code, and optional
data remain available in `extensionFailure`; the CLI does not replace the
failure with another interpreter or report it only through stderr.

An explicitly supplied extension that does not apply to a path leaves that path
available to built-in dispatch or counts it as unsupported. Invalid glob syntax,
an unknown format mapped to multiple media types, and overlapping built-in and
extension candidates are usage failures because the requested dispatch is not
well-defined.

## Agent Usage

The ordinary traversal is:

```text
related -> select relevant neighbors -> read selected observations
```

The Agent uses `--json` only when it needs exact filtering, bulk selection, or
stable field access. The full normalized `inspect` JSON remains available for
protocol-level evidence and editing workflows.

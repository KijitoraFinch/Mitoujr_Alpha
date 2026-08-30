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
- Keep Reference definitions, actual Reference uses, and semantic
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

### ReferenceUse

A `ReferenceUse` records an actual syntactic use.

```text
ReferenceUse
  source observation
  optional containing region
  source byte range
  target:
    named ReferenceId
    or direct RegionAddress
```

A Markdown link with a non-empty fragment uses the fragment as the existing
Origin-scoped `ReferenceId`. A workspace-relative Markdown link without a
fragment is a direct occurrence targeting the whole observation. The source is the
smallest declared region containing the link, or the whole source observation when
no declared region contains it. Repeated uses of one named reference remain
distinct occurrences even though the interpreter emits only one declaration
for that `ReferenceId` and target.

Use identity is the tuple of source Observation and source byte range within
one immutable workspace observation. It is intentionally not a persistent
semantic identifier.

### Relation

A `Relation` is an explicit predicate-bearing edge, such as `supported-by` or
`contradicts`. The initial standard projection derives relations
deterministically from annotations whose object is a region or reference.
Literal-valued annotations are not graph edges.

Reference uses use the reserved display predicate `references`; this
does not turn them into semantic `Relation` values.

### WorkspaceGraphSnapshot

`WorkspaceGraphSnapshot` is an immutable value derived from one workspace scan
and one fixed `RegistrySnapshot`:

```text
observations
sidecar snapshots
regions
annotation index
reference index
reference uses
relations
reference edges
diagnostics
coverage
```

The graph keeps direction per edge. Two opposite edges are not collapsed into a
`bidirectional` edge because predicates may be asymmetric.

The implementation constructs the snapshot for each query. A future
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
query. `--extension-registry` loads all installed capability roles and is
mutually exclusive with those options. Each stable graph-construction attempt
uses an independent checked session per Observation and calls `monika.interpretObservation` only
for paths matching the manifest's applicability, in canonical observation-ID
order. Applicable Annotation and Reference Extractors run additively after the
selected Interpreter. Extension Origins discovered from definitions and direct
uses are observed by their exact Resource Observer; newly extracted uses are
followed to a fixed point. Built-in interpreters remain available for other paths. If a built-in and the extension both apply to one
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

`read` renders one fixed Observation for direct Agent reading. It uses one
stable retained-handle Observation and returns:

- the ObservationType and content identity;
- declared regions and summaries;
- named references and targets;
- explicit annotations;
- the exact observation content.

`read` is not another JSON protocol. An Agent that needs the full normalized
Observation uses `monika inspect` instead. Warnings, including an unsupported
Interpreter, are rendered with the Whole Region and fixed content. Error
diagnostics fail the read rather than returning a body whose associated
explicit information may be incomplete.

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
`CommandResult` envelope. Version 6 includes typed Reference and Relation edges,
source and target resolution, normalized diagnostics, and the complete coverage
shape:

```json
{
  "schemaVersion": "6",
  "status": "incomplete",
  "query": {
    "observation": "docs/linking.md",
    "direction": "both",
    "limit": 50
  },
  "matches": [],
  "diagnostics": [],
  "coverage": {
    "primaryResources": 5,
    "observed": 5,
    "interpreted": 2,
    "unsupported": 3,
    "failed": 0,
    "metadataDiscovered": 1,
    "metadataDecoded": 1,
    "metadataFailed": 0,
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
workspace Observation exit 3. A successfully constructed but incomplete graph
has `status: "incomplete"` and reports its coverage. It exits 1 when the result
contains an effective error Diagnostic and otherwise exits 0. Unsupported
Observations count toward incomplete coverage; they are not fabricated as
failures.

Diagnostics found while processing a supported Observation increment failed
coverage and remain in the result. Values and edges that were independently
validated before another operation failed remain in the stable partial graph;
the failed operation does not fabricate an empty extraction, resolution, or
relation. Coverage and diagnostics therefore distinguish that partial graph
from a complete empty result.

If an Extension session for one discovered Observation cannot start or
initialize, a stable partial graph returns `status: "incomplete"`, retains its
inventory coverage, and includes an `extension-failure` diagnostic. A failure
before any stable graph exists uses `status: "failed"` and zero coverage. Both
JSON and text forms are written to stdout and exit 1 when the Diagnostic has
effective severity `error`. The Extension operation, code, JSON-RPC code, and optional
data remain available in `extensionFailure`; the CLI does not replace the
failure with another interpreter or report it only through stderr.

An explicitly supplied extension that does not apply to a path leaves that path
available to built-in dispatch or counts it as unsupported. Invalid glob syntax,
duplicate exact capability identities, and multiple applicable Interpreter
candidates are usage failures because the requested dispatch is not
well-defined. ObservationType matching is exact on `name` and `version`.

## Agent Usage

The ordinary traversal is:

```text
related -> select relevant neighbors -> read selected observations
```

The Agent uses `--json` only when it needs exact filtering, bulk selection, or
stable field access. The full normalized `inspect` JSON remains available for
protocol-level evidence and editing workflows.

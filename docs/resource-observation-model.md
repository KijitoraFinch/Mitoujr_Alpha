# Resource and Observation Model

This document maps the conceptual definitions in
[`設計原則案.md`](../設計原則案.md) to the reference implementation. It does
not make OCaml, a filesystem, MIME types, or byte strings part of the extension
contract.

## Stable Values

The core keeps the following responsibilities separate:

```text
ResourceObserver(name, version)
× Origin(observer, locator)
  -> Observation | Failure

ObservationType(name, version)
ObservationIdentity(ObservationType, key)
Observation(Origin, ObservationIdentity, Representation)

Interpreter(name, version)
× Observation
  -> Interpretation | Failure

Interpreter(name, version)
× Observation
× Selector
  -> Region | Failure
```

An `Origin` is a declarative locator, not an instruction to fetch data. Built-in
origins cover workspace files, Git objects, web resources, generated values,
and external URIs. `extension` origins add an exact Resource Observer identity
(name and version) and a normalized protocol value as the opaque locator. For
example, a GitHub Issue observer can use observer `github.issue@1` and locator
`{"owner":"example","repository":"project","issue":42}`. Core canonicalizes
and compares the locator but does not interpret it.

An `ObservationType` is a versioned name assigned by a Resource Observer and
consumed by an Interpreter. Examples include
`text/markdown@1`, `language.rust.source@1`, and `github.issue@1`. It is not
restricted to a MIME type. Changing the version means changing the contract for
the observable value.

An `ObservationIdentity` consists of an observation type and a non-empty stable
key chosen by the observer. The observer is responsible for ensuring that the
same identity means the same type and observable value. File observations use
SHA-256 and byte length as one adapter; external Resource Observers can use a
revision, ETag, immutable object identifier, or a canonical digest. The
abstraction does not require every Resource Observer to materialize one byte
string.

An `Observation` is a fixed value for one operation. Its host-owned
representation is either exact bytes or a schema-named normalized protocol
value. Byte representations carry a matching `ContentIdentity`; structured
representations do not pretend to be files or byte streams. Re-observing the
same origin may produce another identity. Existing observations are values and
are not updated in place.

An `Interpretation` is the explicit Region structure an interpreter derives
from one already fixed observation, together with the semantics needed to
resolve and compare those Regions. Annotation and Reference declarations, their
storage locations, and reconciliation are a separate model defined in
[`annotation-reference-storage-model.md`](annotation-reference-storage-model.md). An
Interpretation does not contain or replace observations; observing a Resource
and producing an Observation is a Resource Observer responsibility.

## Region Resolution

`Region_resolution.t` is the complete semantic input to exact region
resolution. Interpreter name and version, observation identity, and selector
all participate in equality. Consequently, these are different operations:

```text
rust.item@1 × source observation A × struct "Request"
rust.item@2 × source observation A × struct "Request"
rust.item@1 × source observation B × struct "Request"
```

A successfully resolved partial `Region` retains that input. A whole region
retains its observation identity but has no interpreter. `CommandResult`
construction rejects a region whose observation identity differs from the
identity of its owning Observation. This prevents a region resolved
from an old file or an old Issue state from being attached to a newer
observation accidentally.

Resolution is exact. A missing struct, renamed symbol, deleted Issue comment,
or ambiguous selector returns an explicit `Failure`. An interpreter must not
substitute a nearby candidate. Repair and inference are separate operations.

## Extension Selectors

Built-in selectors cover whole observations, named regions, text ranges, and
JSONL row filters. An extension-specific selector is a pair of a schema name
and a normalized JSON value. Core validates and compares the value but does not
interpret it. Object field order is canonicalized, duplicate fields and invalid
UTF-8 are rejected, and integers stay inside the protocol safe range.

This is not a source-language or symbol-specific escape hatch. The same shape
can describe an AST node, a function or type, a GitHub Issue comment or thread,
a PDF page area, a table column or row group, an experiment interval, or a
observer-defined subdivision that does not exist yet. Its named schema lets the
matching interpreter validate and explain that selector without adding a new
core variant.

## Observable Observation Shape

Schema version 10 exposes the semantic `Observation` directly. Every observation
has an ID, origin, `ObservationIdentity`, and explicit `representation`.
`representation.kind` is `bytes` or `structured`; structured values carry their
schema identity and canonical protocol value. `ContentIdentity` is present for
byte-backed observations and absent for structured observations. There is no
second content-only wrapper and no implicit ObservationType conversion.

## Extension Authoring Boundary

An extension may be implemented in any language. The OCaml modules are the
reference implementation's invariant-preserving values, not an ABI and not a
required SDK. Protocol version 1 exchanges schema-versioned values for the
following implemented operations:

```text
interpretObservation(
  InterpreterIdentity,
  Observation
) -> Interpretation | Failure

resolveRegion(
  InterpreterIdentity,
  Observation,
  Selector
) -> Region | Failure

classifyRegionExtents(
  InterpreterIdentity,
  Observation,
  Region,
  Region
) -> Equal | Contains | ContainedBy | Overlaps | Disjoint | Failure

extractReferences(
  ReferenceExtractorIdentity,
  Observation,
  Interpretation?
) -> ReferenceExtraction | Failure

extractAnnotations(
  AnnotationExtractorIdentity,
  Observation,
  Interpretation?
) -> AnnotationExtraction | Failure

observeResource(
  ResourceObserverIdentity,
  ExtensionOrigin
) -> Observation | Failure

audit(
  AuditorIdentity,
  WorkspaceGraphSnapshot,
  AuditPolicy
) -> DiagnosticList | Failure

derive(
  DeriverIdentity,
  WorkspaceGraphSnapshot,
  DeriveRequest
) -> ProposedPatchList | Failure
```

The relation is read from the left Region to the right Region. The five values
are exhaustive and mutually exclusive for comparable extents. Swapping the
arguments exchanges `Contains` and `ContainedBy`; the other values are
symmetric. `Equal` is an equivalence relation. Strict containment is
irreflexive, asymmetric, and transitive. Region IDs and selector syntax do not
define extent equality.

Transport, process lifetime, representation transfer, and authentication are
separate from this semantic model. For byte representations, the runtime sends
the exact Observation bytes as a host-owned stream and does not expose a
filesystem path, URI, or content handle. Structured representations travel as
schema-named normalized JSON values without a byte stream. Resource Observer
byte output uses the bounded reverse stream and is fixed by the host before use.
The language-neutral schema and
conformance fixtures do not serialize OCaml implementation values.

An Agent-authored Resource Observer or Interpreter should need to define only:

- one stable Resource Observer or Interpreter name and version;
- the observation types it produces or accepts;
- a declarative selector schema when it resolves partial regions;
- deterministic identity and exact-resolution rules;
- bounded failures with stable codes;
- proposed patches instead of direct workspace writes, if it derives edits.

It must not implement a Monika-specific object hierarchy. A Rust symbol
Interpreter and a GitHub Issue Resource Observer can remain small, independent
extensions because both meet the same value and operation contracts.

## Reference Implementation Modules

- `Origin`: built-in and extension resource locators.
- `Observation_type`: versioned observation kinds.
- `Observation_identity`: type-qualified stable observation keys.
- `Observation`: fixed origin, identity, and host-owned representation values.
- `Resource_observer`: exact observer name/version identities.
- `Normalized_value`: canonical protocol-safe structured values.
- `Interpreter`: versioned interpretation rules.
- `Interpretation`: validated Region structure and Region operations for one
  fixed observation. Annotation and Reference occurrences are separate typed
  results.
- `Region_resolution`: the deterministic resolution input.
- `Region`: whole or exactly resolved regions tied to one observation.
- `Annotation_occurrence` and `Reference_definition_occurrence`: semantic
  values paired with their SourceLocation.
- `Reference_use`: graph evidence distinct from a Reference definition.
- `Sidecar_snapshot`: fixed metadata bytes, separate from primary Observations.
- `Workspace_graph_snapshot`: fixed observations, indexes, edges, endpoint
  resolution, diagnostics, and Coverage consumed by Auditor and Deriver roles.
- `Failure`: explicit observation, interpretation, extraction, audit, derive,
  or resolution failure values.

These modules contain no extension loading, network access, command execution,
or mutable registry.

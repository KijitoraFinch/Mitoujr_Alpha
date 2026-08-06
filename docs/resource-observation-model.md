# Resource and Observation Model

This document maps the conceptual definitions in
[`設計原則案.md`](../設計原則案.md) to the reference implementation. It does
not make OCaml, a filesystem, MIME types, or byte strings part of the extension
contract.

## Stable Values

The core keeps the following responsibilities separate:

```text
Origin(provider, locator)
  -> attempts to identify a Resource again

ObservationType(name, version)
ObservationIdentity(ObservationType, key)
Observation(Origin, ObservationIdentity)

Interpreter(name, version)
× ObservationIdentity
× Selector
  -> Region | Failure
```

An `Origin` is a declarative locator, not an instruction to fetch data. Built-in
origins cover workspace files, Git objects, web resources, generated values,
and external URIs. `extension` origins add a provider name and an opaque
locator. For example, a GitHub provider can use provider `github.issue` and
locator `github://owner/repository/issues/42`. Core compares those values but
does not interpret the locator.

An `ObservationType` is a versioned, provider-readable name. Examples include
`text/markdown@1`, `language.rust.source@1`, and `github.issue@1`. It is not
restricted to a MIME type. Changing the version means changing the contract for
the observable value.

An `ObservationIdentity` consists of an observation type and a non-empty stable
key chosen by the observer. The observer is responsible for ensuring that the
same identity means the same type and observable value. File observations use
SHA-256 and byte length as one adapter; external providers can use a revision,
ETag, immutable object identifier, or a canonical digest. The abstraction does
not require every provider to materialize one byte string.

An `Observation` is a fixed descriptor for one operation. Re-observing the same
origin may produce another identity. Existing observations are values and are
not updated in place.

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
identity of its owning artifact descriptor. This prevents a region resolved
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
provider-defined subdivision that does not exist yet. Its named schema lets the
matching interpreter validate and explain that selector without adding a new
core variant.

## Artifact Compatibility Layer

The schema-version-6 `ArtifactDescriptor` remains the observable compatibility
shape for current file-oriented commands. In the reference implementation an
`Artifact.t` owns an `Observation.t`. Its optional `mediaType` becomes a
version-1 `ObservationType`, and its `ContentIdentity` becomes a content-backed
`ObservationIdentity`. An absent media type maps to
`application/octet-stream@1` internally.

`Artifact` is therefore not the general definition of a resource or an
observation. It is the current command-envelope adapter. Version 6 exposes an
interpreter version whenever an interpreter is present. Future protocol
versions may expose observation type and observation identity directly without
changing their semantic responsibilities.

## Extension Authoring Boundary

An extension may be implemented in any language. The OCaml modules are the
reference implementation's invariant-preserving values, not an ABI and not a
required SDK. A runtime protocol must exchange schema-versioned values for two
logical operations:

```text
observe(Origin) -> Observation | Failure

resolveRegion(
  InterpreterIdentity,
  Observation,
  Selector
) -> Region | Failure
```

Transport, process lifetime, payload streaming, authentication, and content
handles are deliberately separate from this semantic model. When the runtime
protocol fixes them, it must use language-neutral schemas and conformance
fixtures rather than serialized OCaml values.

An Agent-authored provider or interpreter should need to define only:

- one stable provider or interpreter name and version;
- the observation types it produces or accepts;
- a declarative selector schema when it resolves partial regions;
- deterministic identity and exact-resolution rules;
- bounded failures with stable codes;
- proposed patches instead of direct workspace writes, if it derives edits.

It must not implement a Monika-specific object hierarchy. A Rust symbol
interpreter and a GitHub Issue provider can remain small, independent
extensions because both meet the same value and operation contracts.

## Reference Implementation Modules

- `Origin`: built-in and extension resource locators.
- `Observation_type`: versioned observation kinds.
- `Observation_identity`: type-qualified stable observation keys.
- `Observation`: fixed origin and identity pairs.
- `Interpreter`: versioned interpretation rules.
- `Region_resolution`: the deterministic resolution input.
- `Region`: whole or exactly resolved regions tied to one observation.
- `Failure`: explicit observation or resolution failure values.

These modules contain no extension loading, network access, command execution,
or mutable registry.

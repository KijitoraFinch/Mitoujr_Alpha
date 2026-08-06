# Extension Protocol

Protocol version 1 fixes the static descriptor surface. Runtime transport and
method invocation remain intentionally unspecified until they can be tested
with deterministic timeouts and bounded messages.

## Static Descriptor

An extension descriptor is a closed JSON object with `protocolVersion: "1"`
and exactly one `capability`. The capability uses
`schemas/capability.schema.json`. It cannot name an executable or contain
procedural configuration. The executable conformance command is:

```sh
monika extension test --descriptor <file>
```

This command validates descriptor conformance only and does not execute the
extension.

## Capabilities

- `artifact-provider`
- `interpreter`
- `annotation-extractor`
- `deriver`
- `auditor`
- `renderer`
- `indexer`

## Planned Runtime Methods

- `describe`
- `observe`
- `canInterpret`
- `listRegions`
- `resolveSelector`
- `extractAnnotations`
- `fingerprintRegion`
- `derive`
- `audit`
- `render`

`observe` consumes an `Origin` and returns an immutable `Observation` or an
explicit failure. `resolveSelector` consumes the extension's interpreter name
and version, a fixed observation, and a declarative selector. Their semantic
contract is specified in
[`docs/resource-observation-model.md`](../docs/resource-observation-model.md).
The eventual wire format must be language-neutral; internal OCaml values are
not wire values.

## Constraints

- Extensions do not write files directly.
- Runtime extension output includes a schema version.
- Extension diagnostics use stable diagnostic codes.
- Extension write requests are returned as proposed patches.
- An extension must not silently move an unresolved selector to a nearby region.

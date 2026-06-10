# Extension Protocol

Phase 0 fixes only the protocol surface that must remain visible while the model
is detailed.

## Capabilities

- `artifact-provider`
- `interpreter`
- `annotation-extractor`
- `deriver`
- `auditor`
- `renderer`
- `indexer`

## Minimum Methods

- `describe`
- `canInterpret`
- `listRegions`
- `resolveSelector`
- `extractAnnotations`
- `fingerprintRegion`
- `derive`
- `audit`
- `render`

## Constraints

- Extensions do not write files directly.
- Extension output includes a schema version.
- Extension diagnostics use stable diagnostic codes.
- Extension write requests are returned as proposed patches.
- An extension must not silently move an unresolved selector to a nearby region.

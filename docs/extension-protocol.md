# Extension Protocol Notes

Extensions provide narrow capabilities. They do not receive permission to mutate
the workspace directly.

The first executable contract is a static descriptor:

```json
{
  "protocolVersion": "1",
  "capability": {
    "type": "interpreter",
    "name": "custom-markdown",
    "version": "1",
    "appliesTo": {
      "mediaTypes": ["text/markdown"],
      "pathGlobs": ["docs/*.md"]
    }
  }
}
```

`monika extension test --descriptor <file>` strictly decodes this object. It
rejects duplicate and unknown fields, `null`, unsupported protocol versions,
invalid capability types, empty strings, duplicate applicability values, and
empty optional objects. A successful test returns the decoded capability in a
schema version 6 command result. The descriptor is declarative: it contains no
command, pipeline, condition, or executable path.

This first test validates only the static protocol boundary. It deliberately
does not load or execute extension code, so success is not a claim that runtime
methods conform. The later runtime protocol must additionally define:

- protocol version negotiation
- JSON-RPC method names
- error objects
- timeout behavior
- deterministic output requirements
- schema references for selectors, annotations, and options

The semantic inputs to `observe` and `resolveRegion` are fixed independently of
that transport in
[resource-observation-model.md](resource-observation-model.md). OCaml module
types and serialized reference-implementation values are explicitly not part
of the extension contract. This allows an Agent to implement a provider or
interpreter in the language most suitable for the observed resource.

The Phase 0 method inventory and constraints remain documented in
[protocol/extension-protocol.md](../protocol/extension-protocol.md).

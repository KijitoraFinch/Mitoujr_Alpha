# Extension Protocol Notes

Extensions provide narrow capabilities. They do not receive permission to mutate
the workspace directly.

The Phase 0 protocol shape is documented in
[protocol/extension-protocol.md](../protocol/extension-protocol.md). Phase 1 and
later phases must define:

- protocol version negotiation
- JSON-RPC method names
- error objects
- timeout behavior
- deterministic output requirements
- schema references for selectors, annotations, and options

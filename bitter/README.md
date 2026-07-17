# Bitter

Bitter is the Rust high-speed implementation. It is currently a checkable
scaffold. It must later match the external behavior fixed by the specification
layer and the OCaml reference implementation.

The first parity slice is the shared protocol-integer decoder. Its boundary
corpus is consumed by Sugar, JSON Schema validation, and Bitter tests. The
command-result and patch decoders remain later parity units.

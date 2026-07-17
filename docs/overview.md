# Overview

Monika treats workspace files, source code, logs, experimental data, web
captures, and unknown blobs as artifacts that can be inspected, related, checked,
and updated through patches.

The first implementation target is not a thin prototype. The repository starts
with a reference implementation in OCaml, a later high-speed implementation in
Rust, and a specification layer that both implementations must satisfy.

## Current Phase

This repository is in Phase 1. The Phase 0 foundation is complete: stable
directories, fixtures, golden-output locations, schema locations, diagnostics,
protocol notes, local checks, and implementation build boundaries are in place.

Sugar, the OCaml reference implementation, now owns the semantic model,
observable normal form, command-result envelope, artifact descriptors,
read-only workspace scanning, deterministic patch semantics, strict patch input
decoding, and the first executable `monika apply` slice for existing regular
file edits. The first executable `monika inspect` slice reads artifacts through
the retained-handle boundary and extracts Markdown and sidecar observations.
Bitter, the later Rust implementation, remains mostly a scaffold,
but its first real parity slice classifies the shared safe-integer and UTF-8
corpora with the same outcomes as Sugar and the specification validator.

The POSIX and Windows filesystem implementations now use handle-relative
traversal and replacement. Mandatory Windows and macOS execution of the
platform-specific containment, reparse, case-folding, and Unicode-folding tests
remains a release gate before the boundary is considered cross-platform safe.

The first check slice resolves Markdown region IDs and strict JSONL row filters
and emits the basic annotation/reference diagnostics. The first derive slice
emits an inline-to-sidecar patch and verifies
`derive -> apply -> derive` idempotency. Resolve snapshots use an explicit
canonical UTC observation time. Additional interpreters, extension execution,
and broader Bitter parity remain later Phase 1 work. Built-in capability
discovery and strict protocol version 1 extension descriptor testing are
executable; descriptor success does not yet claim runtime extension method
conformance.

The local and CI checks also stage Sugar into a temporary installation prefix
and execute the installed CLI. Homepage, issue tracker, and development
repository metadata follow the Git remote. A public package and versioned
release archive still require the repository owner's authorship, maintainer,
license, and version decisions.

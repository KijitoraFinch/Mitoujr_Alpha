# Overview

Monika treats workspace files, source code, logs, experimental data, web
captures, and unknown blobs as observations that can be inspected, related, checked,
and updated through patches.

The first implementation target is not a thin prototype. The repository starts
with a reference implementation in OCaml, a later high-speed implementation in
Rust, and a specification layer that both implementations must satisfy.

## Current Phase

This repository is in Phase 1. The Phase 0 foundation is complete: stable
directories, fixtures, golden-output locations, schema locations, diagnostics,
protocol notes, local checks, and implementation build boundaries are in place.

Sugar, the OCaml reference implementation, now owns the semantic model,
observable normal form, command-result envelope, fixed Observations and SidecarSnapshots,
read-only workspace scanning, deterministic patch semantics, strict patch input
decoding, and executable `monika apply` paths for safe creation and existing
regular-file edits. `monika inspect` reads observations through the retained-handle
boundary and extracts built-in Markdown plus Sidecar metadata or dispatches
`monika.interpretObservation` to an explicitly supplied temporary interpreter
extension. `monika read` uses the same registry or temporary Extension boundary
and renders the fixed host-owned content for an Agent.
An immutable installed registry supplies all implemented external roles. Exact
Resource Observers fix Extension-Origin values; Interpreters are uniquely
selected by ObservationType and applicability; Annotation and Reference
Extractors are additive; Auditors consume one WorkspaceGraphSnapshot; and an
exact Deriver returns patches through the normal apply boundary. No role uses
fallback priority after a failure.
Bitter, the later Rust implementation, remains mostly a scaffold, but its first
real parity slice classifies the shared safe-integer and UTF-8 corpora with the
same outcomes as Sugar and the specification validator.

The POSIX and Windows filesystem implementations now use handle-relative
traversal and replacement. Mandatory Windows and macOS execution of the
platform-specific containment, reparse, case-folding, and Unicode-folding tests
remains a release gate before the boundary is considered cross-platform safe.

Check resolves Markdown region IDs and strict JSONL row filters from a fixed
WorkspaceGraphSnapshot and emits annotation/reference and external Auditor
diagnostics. Derive consumes one explicitly selected occurrence from the same
snapshot boundary, dispatches a built-in or installed Deriver, preserves
unrelated derived records, emits an inline-to-sidecar patch, and verifies
`derive -> apply -> derive` idempotency. Resolve snapshots use an explicit
canonical UTC observation time. Sugar's bounded stdio JSON-RPC runtime executes
session initialization, Resource observation, interpretation, both Extractor
roles, cross-interpreter Region resolution, Region extent classification,
audit, and derive inside a fail-closed operating-system sandbox. It transfers
byte-backed content through bounded streams in both directions and carries
schema-named structured Observations inline. `monika extension test` invokes
every method declared by the selected capability with typed conformance values.
Reusable session pools, additional standard Interpreters, and broader Bitter
parity remain later Phase 1 work. Static manifest checking remains available
without starting an Extension process.

The local and CI checks also stage Sugar into a temporary installation prefix
and execute the installed CLI. A release workflow builds single-file CLIs for
four OS/architecture targets and packages the three bundled Skills with a
closed integrity manifest and checksums. A successful `pre-alpha` push produces
one immutable, published prerelease derived from the commit identity. A
manually selected SemVer tag instead produces a draft prerelease for owner
promotion. Homepage, issue tracker, development repository, authorship, and
maintainer metadata follow the Git repository. Publishing outside the
authorized internal group still requires an explicit license decision.

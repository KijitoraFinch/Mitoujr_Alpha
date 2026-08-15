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
decoding, and executable `monika apply` paths for safe creation and existing
regular-file edits. `monika inspect` reads artifacts through the retained-handle
boundary and extracts built-in Markdown and sidecar observations or dispatches
`monika.observe` to an explicitly supplied temporary interpreter extension.
Bitter, the later Rust implementation, remains mostly a scaffold, but its first
real parity slice classifies the shared safe-integer and UTF-8 corpora with the
same outcomes as Sugar and the specification validator.

The POSIX and Windows filesystem implementations now use handle-relative
traversal and replacement. Mandatory Windows and macOS execution of the
platform-specific containment, reparse, case-folding, and Unicode-folding tests
remains a release gate before the boundary is considered cross-platform safe.

The first check slice resolves Markdown region IDs and strict JSONL row filters
and emits the basic annotation/reference diagnostics. The first derive slice
emits an inline-to-sidecar patch and verifies
`derive -> apply -> derive` idempotency. Resolve snapshots use an explicit
canonical UTC observation time. Sugar's bounded stdio JSON-RPC runtime executes
`monika.describe`, `monika.observe`, and same-session `monika.resolveRegion` for
the explicitly supplied temporary interpreter path. Installed extension
discovery, cross-interpreter dispatch, reusable session pools, additional
interpreters, and broader Bitter parity remain later Phase 1 work. Static and
live descriptor checks are distinct from the runtime-method CLI goldens that
exercise the implemented ad hoc `inspect` and `resolve` paths.

The local and CI checks also stage Sugar into a temporary installation prefix
and execute the installed CLI. A release workflow builds single-file CLIs for
four OS/architecture targets and packages the three bundled Skills with a
closed integrity manifest and checksums. A successful `pre-alpha` push produces
one immutable, published prerelease derived from the commit identity. A
manually selected SemVer tag instead produces a draft prerelease for owner
promotion. Homepage, issue tracker, and development repository metadata follow
the Git remote. Publishing outside the authorized internal group still requires
the repository owner's authorship, maintainer, and license decisions.

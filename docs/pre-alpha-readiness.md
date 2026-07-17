# Pre-alpha Distribution Readiness

This document defines the release claim for the first pre-alpha distribution
and records the evidence required to make that claim. A configured check is not
evidence that it passed on another platform.

## Distribution Scope

The first pre-alpha distribution contains the Sugar OCaml reference library and
the installable `monika` CLI, together with the repository specification,
schemas, fixtures, and golden outputs. The executable command surface is:

- `monika scan`
- `monika inspect`
- `monika resolve`
- `monika check`
- `monika derive`
- `monika apply`
- `monika capabilities`
- `monika extension test --descriptor`

The extension command validates the static protocol version 1 descriptor. It
does not claim runtime extension-method conformance. Bitter remains the second
implementation scaffold and is checked for shared integer and UTF-8 domains; it
is not a pre-alpha executable distribution artifact.

## Required Gates

| Gate | Required evidence | Current state |
| --- | --- | --- |
| Semantic and CLI behavior | `make check`, including real CLI goldens and idempotency checks | Passes locally |
| Schema compatibility | schema version 4, standalone schemas, strict JSON and semantic validation | Passes locally |
| Install set | isolated `sugar/` package-mode build, tests, temporary-prefix install, installed CLI golden | Passes locally via `tools/check_distribution.py` |
| Filesystem containment | platform-gated tests on Linux, macOS, and Windows | Matrix configured; macOS and Windows results are not yet observed for this worktree |
| Package metadata | `opam lint sugar/monika_sugar.opam` | Fails: maintainer, authors, and license are absent |
| Release identity | owner-approved pre-alpha version and corresponding immutable tag | Not decided |
| Legal distribution | owner-approved license text and matching opam license identifier | Not decided |
| Reproducible source artifact | artifact built from the immutable release commit after all gates pass | Not yet produced |

`make release-check` executes all locally provable gates and then runs
`opam lint`. It must remain failing while mandatory public-package metadata is
absent; bypassing that failure is not a release procedure.

## External Evidence

The latest public workflow for the current base commit is GitHub Actions run
`28583012036`. It predates the tracked opam manifest and matrix workflow and
failed because Dune was not installed. It does not prove or disprove the current
worktree on macOS or Windows. Current evidence requires committing and pushing
this worktree, then observing every matrix job on the exact release commit.

## Owner Decisions Required

Before producing or publishing an archive, the repository owner must provide:

- the maintainer name and contact used by opam;
- the author list;
- the license identifier and license text;
- the pre-alpha version.

Homepage, issue tracker, and development-repository metadata are derived from
the configured Git remote. They should be reviewed with the other metadata but
do not require inventing personal or legal identity.

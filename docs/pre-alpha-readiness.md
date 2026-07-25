# Pre-alpha Internal Distribution Readiness

This document defines the release claim for the first pre-alpha distribution
and records the evidence required to make that claim. The distribution is an
internal source handoff to recipients who use Codex. It is not a public opam
package or a public binary release. A configured check is not evidence that it
passed on another platform.

## Distribution Scope

The handoff contains this repository at an identified commit, including the
Sugar OCaml reference library, the installable `monika` CLI, the specification,
schemas, fixtures, and golden outputs. The recipient gives Codex the source
location, the source identity, and the request in
[codex-installation.md](codex-installation.md).
The handoff also contains the `monika-update` and `monika-report` Codex Skills.
The former performs verified source updates with rollback state; the latter
collects a raw-session bundle and submits it to the separately administered
private repository `MitouJr-2026/reports`.

The executable command surface is:

- `monika scan`
- `monika read`
- `monika related`
- `monika inspect`
- `monika resolve`
- `monika check`
- `monika derive`
- `monika apply`
- `monika capabilities`
- `monika --version`
- `monika extension test --descriptor`

The extension command validates the static protocol version 1 descriptor. It
does not claim runtime extension-method conformance. Bitter remains the second
implementation scaffold and is checked for shared integer and UTF-8 domains; it
is not a pre-alpha executable distribution artifact.

## Required Gates

| Gate | Required evidence | Current state |
| --- | --- | --- |
| Semantic and CLI behavior | `make check`, including real CLI goldens and idempotency checks | Must pass on the final handoff commit |
| Schema compatibility | schema version 4, standalone schemas, strict JSON and semantic validation | Must pass on the final handoff commit |
| Install set | isolated `sugar/` package-mode build, tests, temporary-prefix install, installed CLI golden | Must pass through `tools/check_distribution.py` |
| Filesystem containment | platform-gated tests on Linux, macOS, and Windows | Matrix must complete on the final handoff commit |
| Installation guide | toolchain, build, test, package and Skill installation and update, installed CLI verification, and copyable Codex requests | Defined in `docs/codex-installation.md` |
| Update Skill | exact commit resolution, durable revision source, old-pin rollback state, installed CLI verification, and self-update-last ordering | Defined in `docs/codex-update-skill.md` |
| Report collection | one raw current-session JSONL prefix, redacted Codex doctor report, Monika version, and integrity manifest | Must pass `tools/test_report_bundle.py` |
| Report transport | authenticated Release-asset upload to the private `MitouJr-2026/reports` inbox without Git history writes | Requires the `report-inbox` Release and recipient GitHub access |
| Source identity | exact commit ID, or archive SHA-256 when Git metadata is absent | Must be recorded for each handoff |
| Recipient verification | Codex report from at least one clean recipient environment | Not yet recorded |

Public opam metadata, a public license grant, an immutable public version tag,
and an opam-repository submission are not gates for this authorized internal
handoff. They become mandatory before distribution outside that group.

## External Evidence

GitHub Actions run `29550894693` executed the Linux, macOS, and Windows matrix
for commit `7ee7002344f128f776f95e160a8a3ebed6d64ef4`. Every job stopped in the
repository bootstrap check because that check recursively inspected an opam
dependency's generated Markdown file. The ad hoc Markdown inspection has since
been removed locally. The current source state must be pushed, and every matrix
job must reach and pass the build, test, golden, distribution, and
platform-gated filesystem steps before handoff.

## Handoff Procedure

1. Select a clean commit and run all local checks available in the producer
   environment.
2. Push the commit and observe the complete CI matrix for that exact commit.
3. Send the repository location and commit ID to the recipient. If a source
   archive is used instead, record and send its SHA-256 digest.
4. Send the applicable installation or update request from
   [codex-installation.md](codex-installation.md).
5. Require Codex to report the installed executable path, toolchain versions,
   and executed checks.
6. Install both bundled Skills and start a new Codex thread.
7. Record at least one successful clean-environment recipient report.

Codex may adapt dependency installation and build commands to the recipient
platform. The installation is successful when the package is installed and the
installed CLI passes the guide's verification commands.

## Deferred Public Release Work

Before any public distribution, decide and add:

- maintainer and author metadata;
- a license identifier and license text;
- a public version and immutable tag;
- a reproducible public source artifact and checksums;
- the intended opam-repository publication layout.

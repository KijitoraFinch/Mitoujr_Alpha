# Pre-alpha Internal Distribution Readiness

This document defines the release claim for the first internal binary
distribution and records the evidence required to make that claim. It is not a
public opam package or a general public license grant. A configured workflow is
not evidence that its platform jobs passed for a particular release tag.

## Distribution Scope

Each handoff is one published release at an immutable SemVer tag. It contains
single-file Sugar CLIs for Linux x86-64, macOS arm64, macOS x86-64, and Windows
x86-64; one OS-independent archive containing `monika`, `monika-update`, and
`monika-report`; a closed release manifest; and `SHA256SUMS`. Source building
from the same commit remains a documented alternative.

`monika` provides concise Agent-facing operating principles,
`monika-update` performs verified binary and Skill updates with rollback state,
and `monika-report` collects either a raw-session diagnostic bundle or a
chat-free proposal-style bundle and submits it to the separately administered
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
- `monika extension test --manifest`

The extension command validates the static protocol version 1 manifest and,
when given an executable, checks the live `monika.initializeSession` response
against that manifest. Runtime methods are exercised through the Sugar `inspect`,
`resolve`, and `related` command paths: their tests cover host-streamed
`monika.interpretObservation`, immutable registry snapshots, cross-interpreter
`monika.resolveRegion`, and multi-Interpreter graph construction. Registry discovery
policy and reusable session pools are outside this candidate scope.
Bitter remains the second implementation scaffold and is checked for shared
integer and UTF-8 domains; it is not a pre-alpha executable distribution
artifact.

This candidate scope becomes a release claim only after the final commit passes
the required gates and its immutable tag, full commit identity, successful
four-target workflow, and recipient verification are recorded below.

## Required Gates

| Gate | Required evidence | Current state |
| --- | --- | --- |
| Semantic and CLI behavior | `make check`, including real runtime-extension CLI goldens and idempotency checks | Must be run and recorded on the final handoff commit; the release workflow does not itself run the separate Bitter scaffold check |
| Schema contract | schema version 9, standalone schemas, strict JSON and semantic validation | Must pass on the final handoff commit |
| Install set | isolated `sugar/` package-mode build, tests, temporary-prefix install, installed CLI golden | Must pass through `tools/check_distribution.py` |
| Binary assets | four relocated CLI smoke tests, deterministic Skill archive, closed manifests, checksums, and tamper tests | Must pass `tools/test_release_assets.py` and the release workflow |
| Filesystem containment | platform-gated tests on Linux, macOS, and Windows | Matrix must complete on the final handoff commit |
| Installation guide | toolchain, build, test, package and Skill installation and update, installed CLI verification, and copyable Codex requests | Defined in `docs/codex-installation.md` |
| Update Skill | exact release resolution, complete asset verification, package-manager-safe migration, CLI/Skill rollback, and self-update-last ordering | Defined in `docs/codex-update-skill.md` |
| Report collection | raw-session diagnostic and chat-free content-only forms, Monika version, closed integrity manifests, and exact entry validation | Must pass `tools/test_report_bundle.py` |
| Report transport | mandatory post-disclosure confirmation, bundle digest revalidation, and host-authenticated Release-asset upload to the private `MitouJr-2026/reports` inbox without Git history writes | Requires the `report-inbox` Release and recipient GitHub access |
| Release identity | immutable SemVer tag, exact commit ID, release manifest, and `SHA256SUMS` | Must be recorded for each handoff |
| Recipient verification | Codex report from at least one clean recipient environment | Not yet recorded |

Public opam metadata, a public license grant, code-signing identities, and an
opam-repository submission are not gates for this authorized internal handoff.
They become mandatory or require an explicit policy decision before broader
distribution.

## External Evidence

GitHub Actions run `29550894693` executed the Linux, macOS, and Windows matrix
for commit `7ee7002344f128f776f95e160a8a3ebed6d64ef4`. Every job stopped in the
repository bootstrap check because that check recursively inspected an opam
dependency's generated Markdown file. The ad hoc Markdown inspection was then
removed.

GitHub Actions run `30333178301` subsequently passed on Linux and macOS for
commit `d9a88062eaf7974077a93c671be9f16589c7c5d2`. Its Windows job reached the
golden CLI execution and failed when `monika scan` returned internal-error exit
code 3. A distributable commit must pass the later build, golden, distribution,
and platform-gated filesystem steps on Windows as well.

The binary release workflow and Intel/Apple-silicon macOS split were added
after that run. No release claim may rely on local macOS packaging alone. A
`pre-alpha` push now produces its immutable tag and published prerelease only
after all four CLI assets and the assembled closed asset set pass in one
workflow execution.

No successful four-target release workflow, immutable release identity, or
clean-recipient verification is recorded in this repository for the current
candidate. Workflow configuration by itself is not release evidence.

## Handoff Procedure

1. Select a clean commit, run all local checks, and push it to `pre-alpha`.
2. Require the automatic release workflow to pass for all four targets and
   create the deterministic
   `v0.0.0-pre-alpha.<commit-timestamp>.g<commit-prefix>` prerelease.
3. Verify the published prerelease's closed asset set, release manifest,
   checksums, tag, and full commit identity.
4. Send the applicable installation request from
   [codex-installation.md](codex-installation.md).
5. Require Codex to report the release tag, commit, selected asset identities,
   installed executable path, CLI checks, and all three installed Skills.
6. Start a new Codex thread and record at least one successful clean-environment
   recipient report.

The installation is successful when the matching binary and all three Skills
have verified identities and the installed CLI passes the guide's commands.

## Deferred Public Release Work

Before any public distribution, decide and add:

- maintainer and author metadata;
- a license identifier and license text;
- a reproducible public source artifact and checksums;
- platform code signing and key-management policy;
- the intended opam-repository publication layout.

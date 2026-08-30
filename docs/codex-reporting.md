# Codex-assisted Reports

This document fixes the collection and transport boundary for reports produced
by the bundled `monika-report` Codex Skill. A diagnostic report can carry the
current Codex session as raw bytes. A content-only report carries a proposal,
issue, complaint, or feedback without the Codex session or diagnostics.
Collection and analysis remain separate.

## Diagnostic Report Scope

A report contains one explicitly selected Codex session. For a report created
inside an active Codex thread, the collector selects the file whose name ends
with the current `CODEX_THREAD_ID`; it must not guess from modification time.
If that environment value is unavailable, collection requires an explicit
session path.

The default Codex state root is `$CODEX_HOME`, or `~/.codex` when that variable
is unset. Current Codex CLI installations store active session JSONL below:

```text
$CODEX_HOME/sessions/YYYY/MM/DD/rollout-...-<thread-id>.jsonl
```

This layout is an adapter boundary, not a Monika-owned log schema. A future
Codex layout change is handled by changing session discovery without changing
the report bundle format.

Current interactive Codex sessions contain timestamped tool-call and tool-output
records, including command results. Report collection preserves those records
without depending on their evolving JSON shape. Codex may limit the amount
stored for one tool output, so the session is evidence of what Codex retained,
not an independent complete execution journal.

Bundle version 1 therefore does not add a second Monika command log. If a future
Codex session format stops retaining command results, or its retained output is
insufficient for diagnosis in practice, Monika should add a timestamped
invocation journal as an explicit new bundle entry and schema version. It must
not silently add another persistent log or claim that it corresponds to a
Codex session without canonical timestamps and command identities.

## Bundle Version 1

The collector produces one ZIP archive with these exact logical entries:

```text
manifest.json
report.md
codex/doctor.json
codex/session.jsonl
monika/version.txt
```

`codex/session.jsonl` is a byte-for-byte prefix of the selected source file,
ending at a newline. Collection may occur while Codex is appending the current
record, so an incomplete final line is excluded. The collector does not decode,
redact, normalize, filter, or otherwise interpret JSONL records.

`codex/doctor.json` is the redacted machine-readable output of
`codex doctor --json`. `monika/version.txt` is the exact stdout of
`monika --version`. `report.md` is the reporter's concise description of the
problem, expected behavior, and actual behavior.

`manifest.json` is UTF-8 JSON using report bundle schema version `"1"`. It
conforms to
[`report-bundle-manifest.schema.json`](../schemas/report-bundle-manifest.schema.json)
and contains:

- a UUID report ID and canonical UTC creation time;
- the fixed destination repository and Release tag;
- the Codex thread ID and source log basename;
- the capture boundary (`complete-lines-prefix`);
- the uncompressed byte length and SHA-256 digest of every other bundle entry.

Absolute local paths are not written into the manifest. ZIP entry names and
manifest fields are closed by the collector implementation.

The bundle excludes Codex authentication, configuration, state databases,
history, memories, other sessions, repository files, and environment-variable
values. The raw selected session can itself contain prompts, tool output, local
paths, source fragments, or secrets that appeared during the thread. It must
therefore be treated as confidential.

## Content-only Bundle Version `content-1`

A proposal, feature request, issue, complaint, or other feedback does not need
chat history merely because Codex helped write it. The collector accepts
`--content-only` with an explicit `--report-kind` of `proposal`, `issue`,
`complaint`, or `feedback`.

The resulting ZIP has exactly these entries:

```text
manifest.json
report.md
monika/version.txt
```

Its manifest uses schema version `"content-1"`, records the report kind, and
sets `sessionIncluded` to `false`. It has no `codex` object. The collector does
not discover a session, run `codex doctor`, or add any other conversation
history in this mode. The same digest validation, disclosure, confirmation,
fixed destination, and upload rules apply to both bundle forms.

## Monika Version

`monika --version` is a text interface intended for humans and report
collection. A binary release reports
`<semver>+<12-character-commit-prefix>`, which can be checked against the
release manifest's full commit. A source build may set an explicit
`source-<commit-prefix>` build identity. Otherwise Dune build information is
used when available, and a build without source provenance reports `unknown`.
The collector does not infer a revision from an unrelated checkout.

This interface is independent of the normalized command-result schema and does
not change command-result schema version 11.

## Mandatory Disclosure And Confirmation

Collection never authorizes upload. After collecting a bundle, the Skill shows:

- the report ID and local bundle path;
- the bundle SHA-256;
- for a diagnostic report, the selected session basename, captured byte count,
  SHA-256, every logical bundle entry, and the warning that the raw session is
  unredacted and may contain prompts, tool calls, command output, local paths,
  source fragments, and secrets;
- for a content-only report, the report kind, every logical bundle entry, and
  the explicit statement that it contains no Codex session, diagnostics, or
  chat history;
- the fixed private repository and Release tag.

The Skill then stops and asks whether that exact report ID and bundle SHA-256
may be uploaded. Only a subsequent, explicit user response authorizes
submission. This applies even when the initial request said to send or report
the problem. Recollection, replacement, or modification of the bundle
invalidates the earlier disclosure and requires a new confirmation.

The uploader requires the confirmed report ID and bundle SHA-256 as separate
arguments. Before network access and again immediately before upload, it
revalidates the exact ZIP entry set, compares every payload entry's byte length
and SHA-256 with the manifest, and checks the complete ZIP SHA-256. A changed
bundle is rejected rather than uploaded under an earlier confirmation.

## Transport

Reports are uploaded to the private GitHub repository
`MitouJr-2026/reports`. A repository administrator creates a long-lived Release
with tag `report-inbox` once. Each report uses a unique asset name derived from
its report ID and is uploaded with:

```sh
gh release create report-inbox \
  --repo MitouJr-2026/reports \
  --title "Monika report inbox" \
  --notes "Confidential Codex-assisted problem report bundles." \
  --prerelease \
  --latest=false

gh release upload report-inbox <bundle> --repo MitouJr-2026/reports
```

The `release create` command is one-time administrator setup; reporters run only
the upload command.

The upload does not create a branch, commit, or pull request and therefore does
not retain raw logs in Git history. The uploader must already be authenticated
with GitHub and authorized to upload Release assets. Collection remains useful
when upload is unavailable: the Skill reports the local bundle path and leaves
the archive unchanged for a later retry.

GitHub authentication and upload require host credential and network access.
An expired or invalid authentication result obtained inside the Codex sandbox
is inconclusive because the sandbox may not be able to read valid host
credentials. The Skill retries the same submission through the normal
host-access approval boundary before asking the user to reauthenticate or
modify GitHub credentials.

Creating a GitHub Issue is intentionally separate and optional. The initial
transport optimizes for a single authenticated upload; issue creation can be
added later if report triage needs a stateful queue.

The Skill must complete the disclosure and receive the subsequent confirmation
defined above before invoking the uploader.

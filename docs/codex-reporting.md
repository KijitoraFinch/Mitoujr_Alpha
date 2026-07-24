# Codex-assisted Problem Reports

This document fixes the collection and transport boundary for reports produced
by the bundled `monika-report` Codex Skill. Collection and analysis are
deliberately separate: the recipient stores Codex's JSONL session log as raw
bytes, and the Monika maintainers interpret evolving Codex record shapes.

## Report Scope

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

## Monika Version

`monika --version` is a text interface intended for humans and report
collection. It uses Dune build information so an installed development build
reports its VCS-derived version when available. A build without source
provenance reports `unknown`; the collector does not infer a revision from an
unrelated checkout.

This interface is independent of the normalized command-result schema and does
not change schema version 4.

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

Creating a GitHub Issue is intentionally separate and optional. The initial
transport optimizes for a single authenticated upload; issue creation can be
added later if report triage needs a stateful queue.

The Skill must show the selected session basename, captured byte count,
SHA-256 digest, destination, and bundle path before an upload. It uploads only
when the user's request explicitly includes sending or submitting the report.

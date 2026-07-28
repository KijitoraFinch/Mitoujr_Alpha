---
name: monika-report
description: Collect and optionally submit either a confidential Monika diagnostic report with the current Codex session or a content-only proposal, issue, complaint, or feedback bundle without chat history. Use when a user asks to report, submit, bundle, or preserve a Monika problem, idea, request, objection, installation problem, or update problem for maintainer review.
---

# Monika Report

Collect either a diagnostic report or a content-only report. Collection and
upload are always separate steps. Never treat the request that started report
collection as upload confirmation.

## Collect

1. Choose the report form from the user's intent:
   - Use a diagnostic report for a failure that needs the current Codex thread
     and diagnostics.
   - Use a content-only report for a proposal, feature request, issue,
     complaint, or other written feedback when chat history is unnecessary.
     Do not collect a Codex session merely because one is available.
2. Write the report in a UTF-8 Markdown file. For a diagnostic report, include
   expected behavior, actual behavior, the relevant Monika command, and
   reproduction context already established in the thread. For a content-only
   report, preserve the user's proposal or concern clearly and label it as
   `proposal`, `issue`, `complaint`, or `feedback`. Do not add guessed facts.
3. Create the summary and output archive in a private temporary directory, not
   in the user's repository.
4. For a diagnostic report, run:

   ```sh
   python3 <skill-directory>/scripts/report_bundle.py \
     --summary-file <summary.md> \
     --output-dir <private-temporary-directory>
   ```

   For a content-only report, run:

   ```sh
   python3 <skill-directory>/scripts/report_bundle.py \
     --summary-file <report.md> \
     --output-dir <private-temporary-directory> \
     --content-only \
     --report-kind <proposal|issue|complaint|feedback>
   ```

5. Read the collector's single JSON result. For a diagnostic report, report the
   selected session basename, captured byte count, session SHA-256, bundle path,
   bundle SHA-256, and fixed destination. For a content-only report, report its
   kind, that no session is included, bundle path, bundle SHA-256, and fixed
   destination.

For a diagnostic report, the collector selects the session matching
`CODEX_THREAD_ID`. If that variable is unavailable, stop and ask for an exact
session path and thread ID; never choose a session by newest modification time.

For a diagnostic report, do not open, summarize, redact, normalize, or filter
the selected JSONL. Do not collect `history.jsonl`, authentication,
configuration, databases, memories, other sessions, or repository files. The
archive is confidential because raw tool output and prompts may contain
sensitive data.

A content-only report contains exactly `manifest.json`, `report.md`, and
`monika/version.txt`. It does not contain a Codex thread, Codex diagnostics, or
other conversation history.

## Disclose And Confirm

After collection, show all of the following before asking for confirmation:

- the report ID, bundle path, and bundle SHA-256;
- for a diagnostic report, the selected session basename, captured byte count,
  session SHA-256, exact five entries, and the warning that
  `codex/session.jsonl` is unredacted and can contain prompts, tool calls,
  command output, local paths, source fragments, and secrets;
- for a content-only report, the report kind, the exact three entries, and the
  explicit statement that no Codex session, diagnostics, or chat history is
  included;
- that the fixed destination is the private
  `MitouJr-2026/reports` repository's `report-inbox` Release.

Then ask whether that exact report ID and bundle SHA-256 may be uploaded and
stop the turn. Upload only after a subsequent user response explicitly confirms
sending that disclosed report. An initial request such as "send this report",
"問題を報告して", or the Skill's default prompt authorizes collection only; it
does not replace this confirmation. A vague response, silence, or confirmation
of another report identity does not authorize upload.

If the bundle is collected again, replaced, or modified after disclosure,
validate it, disclose its new identity, and obtain confirmation again.

## Submit

Submission requires host network and credential access. Run the submission
outside the Codex sandbox through the normal approval boundary. Do not infer
that GitHub credentials are expired from a check performed inside the sandbox:
the sandbox may be unable to read otherwise valid host credentials. If GitHub
authentication fails in the sandbox, retry the same submission with host access
before asking the user to reauthenticate or modify credentials.

After the required user confirmation, pass the disclosed report ID explicitly:

```sh
python3 <skill-directory>/scripts/submit_report.py <bundle.zip> \
  --confirmed-report-id <disclosed-report-id> \
  --confirmed-bundle-sha256 <disclosed-bundle-sha256>
```

The uploader revalidates the exact entry set and every manifest byte length and
SHA-256 before upload. Return the asset URL printed by the script. Do not create
a branch, commit, pull request, GitHub Issue, Gist, or alternate upload. Do not
retry with a different destination when GitHub authentication, repository
access, or the `report-inbox` Release is unavailable. Preserve the local bundle
and report the specific failure so it can be submitted later.

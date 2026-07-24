---
name: monika-report
description: Collect and optionally submit a confidential Monika problem report containing the current Codex session JSONL, redacted Codex diagnostics, Monika implementation version, and a concise human summary. Use when a user asks to report, submit, bundle, or preserve a Monika failure, unexpected result, installation problem, or update problem for maintainer investigation.
---

# Monika Report

Collect one current Codex thread without interpreting its evolving JSONL record
shape. Upload only when the user explicitly asks to send or submit the report.

## Collect

1. Summarize the problem in a UTF-8 Markdown file. Include expected behavior,
   actual behavior, relevant Monika command, and reproduction context already
   established in the thread. Do not add guessed facts.
2. Create the summary and output archive in a private temporary directory, not
   in the user's repository.
3. Run:

   ```sh
   python3 <skill-directory>/scripts/report_bundle.py \
     --summary-file <summary.md> \
     --output-dir <private-temporary-directory>
   ```

4. Read the collector's single JSON result. Report the selected session
   basename, captured byte count, session SHA-256, bundle path, and fixed
   destination.

The collector selects the session matching `CODEX_THREAD_ID`. If that variable
is unavailable, stop and ask for an exact session path and thread ID; never
choose a session by newest modification time.

Do not open, summarize, redact, normalize, or filter the selected JSONL. Do not
collect `history.jsonl`, authentication, configuration, databases, memories,
other sessions, or repository files. The archive is confidential because raw
tool output and prompts may contain sensitive data.

## Submit

Treat an explicit request such as "send this report", "submit the report", or
"問題を報告して" as authorization to upload the collected archive. A request to
only collect, inspect, or prepare a report does not authorize upload.

Before uploading, state the bundle path, selected session basename, captured
byte count, SHA-256, and `MitouJr-2026/reports`. Then run:

```sh
python3 <skill-directory>/scripts/submit_report.py <bundle.zip>
```

Return the asset URL printed by the script. Do not create a branch, commit,
pull request, GitHub Issue, Gist, or alternate upload. Do not retry with a
different destination when GitHub authentication, repository access, or the
`report-inbox` Release is unavailable. Preserve the local bundle and report the
specific failure so it can be submitted later.


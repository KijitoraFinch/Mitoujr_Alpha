---
name: monika
description: Use the installed Monika CLI as an Agent-facing boundary for inspecting explicit workspace information, following references and relations, checking consistency, and applying Monika-derived patches. Use when the user asks to use Monika or when a task needs artifact, region, reference, annotation, or workspace-relation awareness.
---

# Monika

Use Monika to obtain explicit, reproducible workspace observations. Choose the
commands and order that best fit the task; do not impose a fixed pipeline.

## Principles

- Prefer `related` and `read` for focused Agent exploration. Use the normalized
  JSON commands when exact fields or editing evidence are needed.
- Check `capabilities` before assuming Monika can interpret a format.
- Treat incomplete coverage and unsupported artifacts as unknown, not as
  evidence that no relation exists.
- Keep `check` read-only. Treat `derive` output as a proposal, validate it, and
  use `apply` for Monika-derived writes.
- Do not bypass a diagnostic, content-identity mismatch, or conflict by directly
  writing the intended result.

## Problems And Missing Capabilities

First distinguish invalid input or an environment problem from a Monika defect.
If Monika crashes, returns an incorrect or unstable result, violates its safety
boundary, or lacks a capability required for the task, explain the finding
briefly and recommend that the user report it with `$monika-report`.

Do not collect or upload a report automatically. After the user agrees, hand
the reproduction context and the required capability or observed failure to
`$monika-report`; that Skill owns disclosure, confirmation, and submission.

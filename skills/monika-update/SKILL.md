---
name: monika-update
description: Update an installed internal Monika source distribution to an exact verified revision, including the Sugar CLI and bundled Codex Skills, while preserving existing source changes and retaining rollback information. Use when a user asks to update, upgrade, refresh, or move Monika to a newer pre-alpha revision.
---

# Monika Update

Update from verified source without treating a moving branch name as the
installed identity. Use the target revision's `AGENTS.md` and
`docs/codex-installation.md` as the authoritative build and verification guide.

Default source and channel:

```text
source: https://github.com/KijitoraFinch/Mitoujr_Alpha.git
channel: refs/heads/pre-alpha
```

An explicit source or revision from the user overrides the corresponding
default.

## Resolve and Snapshot

1. Resolve the requested revision to one full Git commit ID. If the user asks
   for the current channel without naming a revision, resolve the default
   channel with `git ls-remote`. Record the commit ID and use it for every
   subsequent checkout and report.
2. Record, without changing state:

   ```sh
   opam switch show
   opam exec -- command -v monika
   opam exec -- monika --version
   opam pin list
   ```

3. Record the existing `monika_sugar` pin target when present. Preserve its
   source directory for rollback. Do not infer the installed revision from an
   unrelated checkout.

If the resolved target already matches the recorded installed identity, still
verify that the CLI and both bundled Skills are present; finish as an
idempotent no-op when they are current.

## Prepare and Verify the Target

Prepare the exact commit in a durable, per-user source directory, not a
temporary directory and not an existing checkout with local changes. Use a
revision-specific directory so an earlier pin remains available for rollback.
Suitable platform locations include:

- macOS: `~/Library/Application Support/Monika/sources/<commit>`
- Linux: `${XDG_DATA_HOME:-~/.local/share}/monika/sources/<commit>`
- Windows: `%LOCALAPPDATA%\Monika\sources\<commit>`

Do not delete an older source directory while an opam pin may still reference
it. Reuse a previously prepared target only after verifying its remote, clean
worktree, and exact `HEAD`.

From the target checkout:

1. Read `AGENTS.md` and the complete update section of
   `docs/codex-installation.md`.
2. Verify `git rev-parse HEAD` equals the resolved target commit and
   `git status --short` is empty.
3. Confirm both `skills/monika-update/` and `skills/monika-report/` contain
   their `SKILL.md` and `agents/openai.yaml`; also confirm the report Skill's
   two scripts are present.
4. Prepare dependencies and run the Python contract checks, report-bundle
   tests, Sugar build and tests, golden validation, and distribution check from
   the guide.

Do not change the installed package or Skills when target verification fails.

## Install and Verify

Use the previously selected opam switch. Point `monika_sugar` at the verified,
durable target and explicitly reinstall it:

```sh
opam pin add monika_sugar <target>/sugar --no-action
opam reinstall monika_sugar --with-test
```

Run every installed-CLI verification command in the guide through
`opam exec`. Confirm `command -v monika`, `monika --version`, capabilities, and
the fixture smoke tests all succeed before updating either Skill.

If package installation or verification fails, restore the recorded previous
pin and reinstall it when that source is available, then re-run its basic CLI
verification. Report both the update failure and rollback result. Do not claim
rollback succeeded without executing the old installation.

## Replace the Bundled Skills

Update only `monika-report` and `monika-update` under the active Codex skills
directory. Preserve every unrelated Skill.

1. Stage complete copies from the verified target on the same filesystem as
   the destination.
2. Replace directories rather than copying over them, so removed files cannot
   remain stale.
3. Keep restorable backups during replacement. Replace `monika-report` first
   and this `monika-update` Skill last. Restore both old directories if either
   replacement fails.
4. Confirm the installed file sets, then remove only the two backups created by
   this update.

The current thread may finish using the already-loaded Skill instructions.
Tell the user that the updated Skills become active in a new Codex thread.

## Report

Report the previous and target identities, source directory, opam switch,
executable path, dependency changes, checks executed, CLI verification, Skill
replacement, and any rollback. Do not delete old revision sources as automatic
cleanup.


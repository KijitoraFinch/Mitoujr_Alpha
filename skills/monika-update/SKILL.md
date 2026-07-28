---
name: monika-update
description: Update an installed Monika binary and its three bundled Codex Skills from one exact verified GitHub Release, with complete staging, post-install verification, and rollback. Use when a user asks to update, upgrade, refresh, or move Monika to another release.
---

# Monika Update

Update the CLI and bundled Skills as one release identity. Do not treat a moving
channel, a branch name, or an independently downloaded file as the installed
identity.

Default repository and channel:

```text
repository: KijitoraFinch/Mitoujr_Alpha
channel: latest published pre-alpha prerelease
```

An explicit repository or release tag from the user overrides the corresponding
default. A release selected from the default channel must be non-draft,
published, marked as a prerelease, and have a tag matching
`v0.0.0-pre-alpha.<commit-timestamp>.g<12-character-commit-prefix>`. Do not use
GitHub's ordinary latest-release endpoint because it excludes prereleases.
Never select a draft release. Read the target release's complete
`docs/codex-installation.md` before changing installed state.

## Resolve and Record

1. Resolve the requested channel once to one tag in the form `v<semver>`.
   For the default channel, list published releases, exclude drafts, require
   the pre-alpha tag pattern and prerelease marker, and select the greatest
   `publishedAt` value. Record the repository, tag, and publication timestamp.
   Use that exact repository and tag for all subsequent downloads and reports.
2. Record without changing state:
   - the path selected by `command -v monika` or its platform equivalent;
   - `monika --version` and `monika capabilities`;
   - whether the selected CLI is inside an opam switch or another
     package-manager-owned location;
   - the active Codex skills directory;
   - the complete file sets of installed `monika-report`, `monika`, and
     `monika-update`.
3. Do not infer an installed release from an unrelated checkout. When the
   current binary has no release identity, record it as an unversioned source
   installation.

If the resolved target matches the recorded CLI identity, still verify the CLI
and all three Skill file identities. Complete as an idempotent no-op only when
the entire observable installation is current.

## Acquire and Verify the Target

Use a private temporary directory outside the user's workspace. From the one
resolved release, download:

- `release-manifest.json`;
- `SHA256SUMS`;
- the one CLI asset whose platform and architecture match the host;
- `monika-skills-<version>.zip`.

Before executing or installing downloaded content:

1. Confirm the release manifest has schema version `1`, the resolved tag, a
   matching SemVer, and one full 40-character Git commit ID.
2. Confirm its closed asset inventory names Linux x86-64, macOS arm64, macOS
   x86-64, Windows x86-64, and the Skill archive exactly once.
3. Confirm the selected CLI's platform and architecture match values observed
   from the host. If no asset matches, stop without changing the installation
   and offer the source-build route from the Installation Guide.
4. Verify the CLI, Skill archive, and release manifest against `SHA256SUMS`.
   Verify each asset's byte count and lowercase SHA-256 against the release
   manifest too.
5. Reject a checksum line for a different basename, duplicate manifest fields,
   duplicate archive entries, absolute archive paths, `..` path components,
   symbolic links, and files outside the declared inventory.
6. Extract the Skill archive without executing it. Validate its internal
   schema-version-1 manifest, release version, commit, exact ordered file
   inventory, byte counts, and SHA-256 values.

Checksums obtained from another repository, release, mirror, or conversation do
not replace the same-release checks. The current release channel is unsigned;
report that the verification establishes release-asset integrity, not
code-signing identity.

Do not change the installed CLI or Skills when any target verification fails.

## Stage the Complete Installation

Keep all staging and rollback backups on the same filesystem as their
destination.

For a binary-managed installation, retain its current CLI path. For a source or
package-manager-managed installation, do not overwrite the managed file. Migrate
to the per-user binary path from the Installation Guide:

- macOS and Linux: `~/.local/bin/monika`;
- Windows: `%LOCALAPPDATA%\Monika\bin\monika.exe`.

Record whether `PATH` selects that destination. Do not uninstall the old opam or
package-manager installation as part of this update.

Stage the CLI as a sibling temporary file with executable permission where
required. Stage complete copies of `monika-report`, `monika`, and
`monika-update` under the active Codex skills directory's filesystem. Do not
stage by copying over installed Skill directories.

Create distinct restorable backups of the existing managed CLI, when present,
and each existing managed Skill. Never use the surrounding `skills` directory
as a replacement or backup target.

## Replace and Verify

Perform effects in this order:

1. Replace the managed CLI file.
2. Execute the CLI through its complete destination path. Require exact
   `monika <version>+<12-character-commit-prefix>` output and an `ok`
   `capabilities` result with the built-in capabilities.
3. Ensure normal command resolution selects the intended CLI path. If another
   package manager still takes precedence, fix only the per-user `PATH`
   selection or stop and roll back; do not overwrite that manager's file.
4. Replace `monika-report` as a complete directory.
5. Replace `monika` as a complete directory.
6. Replace this `monika-update` directory last.
7. Compare all three installed file sets, byte counts, and SHA-256 values with
   the validated Skill manifest.

Removed files from an older Skill must not survive the directory replacement.
Preserve every unrelated Skill.

Only after all verification succeeds may the backups created for this update
be removed. Remove only those exact backups and the private staging directory.
Do not delete source checkouts, opam pins, package-manager state, or unrelated
temporary files.

## Roll Back as One Unit

Any failure after the first replacement rolls back the managed CLI and all
three managed Skill directories to their recorded previous states. A Skill
that did not previously exist is removed only if this update created that exact
directory. Do not report successful rollback until:

- the previous CLI executes through its restored complete path;
- its recorded `--version` behavior is restored;
- all three previous Skill file sets are restored;
- unrelated Skills remain unchanged.

If rollback cannot be completed, preserve the backups and staging evidence,
report the exact remaining state, and request user direction. Do not continue
with a mixed-release installation.

## Report

Report:

- previous CLI identity and path;
- target repository, tag, version, and full commit;
- host platform and architecture;
- selected asset names and verified SHA-256 values;
- whether the update migrated away from an opam or package-manager path;
- CLI replacement and post-install command results;
- all three Skill replacements and manifest comparison;
- rollback, backup preservation, and any unsigned-release limitation.

The current thread continues with the already-loaded Skill instructions. Tell
the user that the updated Skills become active in a new Codex thread.

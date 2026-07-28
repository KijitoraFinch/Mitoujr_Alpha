# Codex-assisted Monika Binary Updates

This document fixes the safety boundary for the bundled `monika-update` Codex
Skill. The Skill updates the single-file CLI and all three bundled Skills from
one exact published GitHub Release. It does not require an OCaml toolchain,
modify a source checkout, or treat a moving release channel as installed state.

## Release Identity

The default repository is `KijitoraFinch/Mitoujr_Alpha`, and the default moving
channel is its latest published GitHub Release. The channel is only a discovery
input. The Skill resolves it once to a `v<semver>` tag and uses that repository
and tag for all downloads, verification, mutation, rollback, and reporting.

The closed release manifest binds that tag and SemVer to one full Git commit and
to each asset's basename, byte count, SHA-256, platform, and architecture.
Release-built CLIs report `<version>+<12-character-commit-prefix>`. The Skill
archive carries its own closed manifest with the same version and full commit.

No asset is executed or installed before both manifest levels and
`SHA256SUMS` have been checked. Checksums downloaded from the same unsigned
release establish transferred-content integrity; they are not a substitute for
future platform code signing.

## Managed State

Before mutation, the Skill records:

- selected executable path and `monika --version`;
- `monika capabilities`;
- whether the path belongs to opam or another package manager;
- active Codex skills directory;
- exact installed file sets for `monika-report`, `monika`, and
  `monika-update`;
- target repository, tag, version, commit, platform, architecture, asset names,
  byte counts, and SHA-256 values.

The normal binary-managed destinations are `~/.local/bin/monika` on macOS and
Linux and `%LOCALAPPDATA%\Monika\bin\monika.exe` on Windows. A source or
package-manager installation migrates to this per-user path instead of
overwriting the manager-owned executable. Removing the old package is outside
the update operation.

## Closed Skill Placement

The Skill archive contains exactly the file inventory fixed by
`schemas/skill-package-manifest.schema.json`. Archive validation rejects
duplicate entries, path traversal, symbolic links, undeclared files, and
content identities that differ from the internal manifest.

Only `monika-report`, `monika`, and `monika-update` below the active Codex
skills directory are managed. Each complete new directory is staged on the
destination filesystem. Existing directories are backed up and replaced as
directories, not overlaid file by file, so removed files cannot remain active.
The surrounding `skills` directory and unrelated Skills are never replacement
targets.

## Effect Ordering

The update proceeds in this order:

1. resolve one published release tag;
2. capture the complete current CLI and Skill state;
3. acquire all target assets into a private temporary directory;
4. validate release identity, target compatibility, checksums, archive safety,
   and every declared file identity;
5. stage the CLI and all three Skills on their destination filesystems;
6. create restorable backups;
7. replace the CLI;
8. execute its complete path and verify version and capabilities;
9. verify ordinary command resolution selects the intended path;
10. replace `monika-report`;
11. replace `monika`;
12. replace `monika-update` last;
13. verify all installed Skill file identities;
14. remove only the backups and staging data created by this successful update;
15. report evidence and require a new Codex thread for Skill discovery.

The CLI is verified before Skill replacement because a new Skill may require a
new command surface. The currently executing update Skill is replaced last
because its instructions are already loaded for the active thread.

## Failure and Rollback

A failure before replacement leaves the installation unchanged. Any failure
after CLI replacement restores the CLI and all three Skills as one unit. A
previously absent managed target is removed only when this update created that
exact target.

Rollback is successful only after the previous CLI executes from its restored
path, its recorded version behavior is observed, all three previous Skill file
sets match, and unrelated Skills remain unchanged. If that cannot be proven,
the Skill retains backups and reports a mixed or uncertain installation instead
of claiming recovery.

## Idempotency

Running the Skill again for the same release revalidates the selected CLI path,
release identity, capabilities, and all three Skill content identities. When
they already match, the update performs no replacements. A matching CLI version
alone is not enough to classify the operation as a no-op.

## Source-build Escape Hatch

If the host platform and architecture have no release asset, the Skill stops
before mutation and offers the source-build section of
[codex-installation.md](codex-installation.md). Source building remains a
separate, explicit installation route. It does not silently weaken target
matching or run a binary built for another platform.

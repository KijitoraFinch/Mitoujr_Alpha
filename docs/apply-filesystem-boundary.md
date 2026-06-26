# Apply Filesystem Boundary

This document fixes the filesystem boundary for the first production
`monika apply` slice. The pure operation remains `Workspace_ops.apply_patch` on
workspace snapshots. The filesystem boundary is responsible for turning a
workspace root and one decoded `ProposedPatch` into the observed file read,
optional file replacement, and `CommandResult`.

## Scope

The first implementation handles one patch against one existing regular
workspace file.

In scope:

- existing regular file targets
- text edits
- dry-run apply
- repeated apply no-op
- identity mismatch and edit conflicts
- safe replacement of file content

Out of scope:

- create patch
- delete patch
- multiple patches in one transaction
- stdin patch input
- persistent snapshot cache updates
- cross-file rollback
- transactional isolation from non-cooperating external writers

## Cross-Platform Model

The filesystem boundary must be implemented through a narrow platform adapter.
Core patch semantics remain platform-neutral; only native path mapping, file
type inspection, temporary file creation, flushing, and replacement are
platform-specific.

The first supported platform families are:

- POSIX-like local filesystems on Linux.
- POSIX-like local filesystems on macOS.
- Windows filesystems addressed through Unicode Windows APIs.

The implementation must not use string-prefix checks to prove containment under
the workspace root. Containment must be established through platform path APIs
and per-component traversal. Platform-specific failures to establish containment
are invalid input or filesystem safety failures; they are not successful no-op
results.

Network filesystems, virtual filesystems, and unusual mount options may weaken
rename and flush guarantees. The first implementation should test on local
filesystems and should report any platform operation failure without claiming
`applied`.

## Root Resolution

`--workspace <dir>` must resolve to an existing directory before any patch target
is inspected. The implementation records the physical workspace root after
resolving the root itself.

Patch targets are `Workspace_path.t` values, not native path strings. The
canonical workspace path is resolved segment by segment under the workspace
root. Absolute paths, dot segments, dot-dot segments, empty segments, encoded
slash, encoded NUL, and non-canonical percent escapes are rejected before this
boundary by `Workspace_path`.

The resolved target must remain inside the workspace root. Any target that
cannot be proven to stay inside the root is invalid and must not be opened for
writing.

The native path mapping is platform-specific:

- On POSIX-like systems, decoded workspace path bytes map to native path bytes.
- On Windows, decoded workspace path bytes must be valid UTF-8 and must map to
  valid Windows path segments. Segments containing Windows-reserved characters,
  control characters, trailing spaces or dots, or reserved device names are
  rejected.
- Core does not normalize Unicode. The filesystem boundary uses the exact
  segment spelling requested by the patch. Tests must not assume that two names
  differing only by Unicode normalization or case are distinct on every
  filesystem.

On case-insensitive or normalization-insensitive filesystems, apply must not use
filesystem folding to find a different logical path. During per-component
resolution, the implementation should verify that the directory entry selected
by the OS matches the requested segment's native spelling. If the exact segment
cannot be found, the target is treated as missing or invalid rather than
rewritten through a folded spelling.

## Symlink Policy

For the first apply implementation, symlink handling is intentionally strict.

- The workspace root may itself be a symlink, but it is resolved once before
  target resolution.
- Symlink path components below the resolved workspace root are rejected.
- A target that is itself a symlink is rejected.
- Parent directories used for the replacement file must be real directories
  under the resolved workspace root.
- On Windows, symlinks, junctions, mount points, and other reparse points below
  the resolved workspace root are rejected for apply.

This policy avoids writing through a path that can redirect outside the
workspace. A later `scan` policy may decide how to report symlinked artifacts,
but `apply` does not write through them in this milestone.

## Target State

The target must be an existing regular file. Missing targets, directories,
devices, FIFOs, sockets, and other non-regular files are not writable artifacts
for this milestone.

The implementation reads the complete current file content and computes its
`Content_identity`. If that identity equals `resultingContentIdentity`, apply
returns no change and performs no write. If it differs from
`expectedContentIdentity`, apply returns an identity conflict and performs no
write.

Only after the expected identity is satisfied does the implementation apply the
patch edits in memory. The resulting content identity must equal the patch's
`resultingContentIdentity`; otherwise the command returns a result identity
conflict and performs no write.

## Dry Run

Dry-run apply performs all decoding, root validation, target safety checks,
current identity checks, edit application, and resulting identity verification.
It never writes a temporary file and never renames a file.

If the patch would apply, dry-run returns a `patches-proposed` result containing
the input patch. If the target already has the resulting content, dry-run
returns `ok`. If any conflict is detected, dry-run returns `conflict`.

## Atomic Replacement

Non-dry-run apply writes the complete replacement content to a temporary file in
the same directory as the target. The target file is not truncated in place.

The replacement sequence is:

1. Read and validate the current target content.
2. Compute the replacement content in memory.
3. Create a uniquely named temporary file in the target directory.
4. Write the full replacement content to the temporary file.
5. Flush and close the temporary file.
6. Atomically rename the temporary file over the target.
7. Re-read the target and verify `resultingContentIdentity`.

The implementation preserves the existing file mode unless a later patch format
explicitly carries metadata edits. Ownership, timestamps, and extended
attributes are not part of the current patch contract.

The platform adapter must choose the replacement primitive explicitly:

- On POSIX-like systems, the replacement primitive is same-directory `rename`
  after writing and flushing the temporary file. The containing directory should
  be flushed after the rename when the platform supports it.
- On Windows, the replacement primitive must have replace-existing semantics,
  such as `ReplaceFileW` or an equivalent wide-character API sequence. The code
  must not assume that a POSIX-style `rename` wrapper has the same overwrite
  behavior on Windows.

The guarantee required here is that readers do not observe a partially written
target file. Power-loss durability depends on the platform and filesystem; the
implementation should request the strongest practical flush supported by the
platform and must not report success until the final target content has been
read back and verified.

## Concurrency Model

`apply` is not a full transaction system in this milestone. It must serialize
with other Monika apply processes for the same target through a best-effort
per-target lock, but it cannot rely on non-cooperating editors, build tools, or
other processes honoring that lock.

To reduce accidental overwrites, the implementation must check the target's
content identity before computing the replacement and again immediately before
the atomic replacement. If the second identity check does not match
`expectedContentIdentity`, apply returns an identity conflict and does not
replace the file.

There is still a platform-dependent race window with non-cooperating writers
between the final identity check and the replacement operation. This limitation
must be covered by tests and documentation before write support is advertised as
safe for concurrent editing workflows. Stronger compare-and-swap replacement or
platform-specific exclusive handles can be added later without changing the
patch format.

## Failure Handling

If failure occurs before the atomic rename, the original target content must
remain unchanged. Temporary file cleanup is best effort, but leftover temporary
files must not be treated as workspace artifacts by apply.

If failure occurs after the rename, or if the implementation cannot prove
whether the rename happened, the command must not return `applied`. It must
report a failure result whose `exitClass` is not `success`. The implementation
must not claim changed artifacts unless the final target content has been read
back and verified against `resultingContentIdentity`.

If the existing conflict algebra cannot represent a filesystem safety failure
precisely enough, the model and schema must be extended before filesystem apply
is implemented. Safety failures must not be collapsed into successful no-op
results.

## Required Tests

The first filesystem apply implementation must include platform-neutral tests
and platform-gated integration tests.

Platform-neutral tests:

- invalid canonical paths are rejected before native path resolution
- dry-run performs no write
- repeated apply returns no change
- identity mismatch does not write
- range and overlap conflicts do not write
- result identity mismatch does not write
- temporary file failure preserves the original target content

POSIX-gated tests:

- symlinked parent directory is rejected
- symlinked target is rejected
- same-directory replacement preserves complete final content
- no-change apply does not rewrite the target

Windows-gated tests:

- reserved device names and reserved characters are rejected
- reparse points below the workspace root are rejected
- case-folded spelling does not rewrite a differently cased logical target
- replacement uses overwrite semantics that work when the target already exists

macOS-gated tests:

- case-folded spelling does not rewrite a differently cased logical target on a
  case-insensitive volume
- Unicode normalization assumptions are not baked into logical path equality

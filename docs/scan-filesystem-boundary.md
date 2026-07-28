# Scan Filesystem Boundary

This document records the filesystem boundary of the first `monika scan`
slice. It distinguishes the observable contract already implemented by Sugar
from the concurrency hardening that is still required.

## Scope

The current slice enumerates existing regular files below one workspace root
and emits an `Artifact` descriptor for each file. Directories are traversal
structure. Symbolic links and other non-regular entries are not artifacts in
this slice and produce `unsupported-filesystem-entry` diagnostics. The separate
`unsupported-artifact` code means that an artifact exists but no capability can
inspect it.

The workspace root is resolved to a physical directory once before traversal.
A symbolic link used as the root is therefore allowed, while symbolic links
encountered below that root are not followed during an unchanging traversal.
Every emitted workspace origin is relative to the resolved root.

## Content Identity

Regular-file content is read in bounded chunks. SHA-256 state and byte length
are accumulated incrementally, so memory consumption does not grow with the
artifact size. The resulting pair is emitted as `ContentIdentity`.

The scan result does not retain file contents. Media-type detection is not part
of this slice, so `mediaType` is omitted.

Content identities cover the bytes present in the workspace; scan does not
normalize line endings. Repository fixtures and goldens therefore have an
explicit LF checkout policy in `.gitattributes`, including on Windows. This
policy fixes test inputs and does not change files in a scanned user workspace.

## Ordering and Failure Results

Directory entries are sorted before recursive traversal, and observable
artifact and diagnostic collections are normalized again before JSON encoding.
Repeated scans of an unchanged workspace therefore produce the same JSON.

An invalid or non-directory workspace root produces `invalid-input`. Failure to
enumerate a directory, inspect an entry, or read a regular file produces an
`internal-error` command result. Scan does not report a successful partial
inventory when an I/O operation required for that inventory failed.

## Consistency and Concurrency Limit

On POSIX, Sugar now retains the root and current directory file descriptors.
Entry inspection uses `fstatat` with no-follow semantics, child directories and
regular files are opened with `openat` and `O_NOFOLLOW`, and enumeration uses a
stream derived from the held directory descriptor. Inspection and content
reading are therefore attached to the opened objects instead of later native
path lookups.

For each regular file, scan records `fstat` identity, size, modification time,
and change time before hashing and compares them with the values after EOF. A
change causes one retry through a newly opened descriptor. If the second
attempt is also unstable, scan returns `internal-error` with the stable
workspace-relative message that the file changed while its identity was being
computed. Scan does not emit a digest assembled across a detected mutation.
Artifact reads used by inspect, resolve, check, and derive apply the same
rule: each retry repeats safe relative path resolution and opens a fresh
descriptor. In particular, they do not seek and reuse a handle after an
unstable Windows read.

This is not an atomic workspace snapshot: unrelated entries can still change
between their individual reads. Windows now traverses with retained directory
handles, enumerates from those handles, opens descendants relative to them, and
classifies reparse points as unsupported entries. Directory enumeration uses
the already-authorized retained handle without reopening the directory by path
or requesting a second access grant. The configured Windows CI job exercises
both inventory scanning and stable artifact reads.

## Required Tests

The portable suite covers regular-file enumeration, stable ordering, content
identities, invalid roots, root symbolic-link resolution, bounded hashing,
unsupported entries, and I/O failures represented as command results.

The POSIX suite also verifies that a retained parent descriptor cannot be
redirected by replacing its original path with a symbolic link. The bounded
mutation retry is shared by production and deterministic
fault-injection tests: one changed observation is retried, while two changed
observations return the stable failure without a third read. Remaining
platform-gated hardening tests must cover Windows reparse points. Apply now has
capability-sensitive integration coverage for case and Unicode spelling
behavior.

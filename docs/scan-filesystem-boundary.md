# Scan Filesystem Boundary

This document records the filesystem boundary of the first `monika scan`
slice. It distinguishes the observable contract already implemented by Sugar
from the concurrency hardening that is still required.

## Scope

The current slice enumerates existing regular files below one workspace root
and emits an `Observation` descriptor for each file. Directories are traversal
structure. Symbolic links and other non-regular entries are not observations in
this slice and produce `unsupported-filesystem-entry` diagnostics. The separate
`unsupported-observation` code means that an observation exists but no capability can
inspect it.

The workspace root is resolved to a physical directory once before traversal.
A symbolic link used as the root is therefore allowed, while symbolic links
encountered below that root are not followed during an unchanging traversal.
Every emitted workspace origin is relative to the resolved root.

## Ignore Rules

Traversal automatically reads regular `.gitignore` and `.monikaignore` files
from each visited directory. Both use Git's ignore-pattern form: blank and
comment lines, escaped leading `#` and `!`, trailing-space escaping, negation,
root-relative and directory-relative slash semantics, directory-only patterns,
`*`, `?`, bracket ranges and POSIX character classes, and the documented `**`
forms. Matching is deterministic and case-sensitive on every platform.

Rules are immutable traversal values. A child directory extends its inherited
rules with its own `.gitignore` followed by its own `.monikaignore`; rules in
the deeper directory therefore have higher precedence, and `.monikaignore`
wins over `.gitignore` at the same level. Within one file, the last matching
rule wins. An excluded directory is not traversed, so a negated rule cannot
re-include a descendant of an excluded parent. This matches Git's traversal
constraint.

Monika applies these patterns to every candidate observation, independently of
whether Git tracks that path. It deliberately does not read the Git index,
`.git/info/exclude`, or a user-level `core.excludesFile`: those inputs are
repository-external or user-specific and would make the same workspace bytes
produce different inventories. Every `.git` entry is excluded as version
control metadata. Ignore files remain ordinary observations unless an applicable
rule excludes them.

Ignore files are opened relative to the retained directory handle and symbolic
links or reparse points are never followed as configuration. Their content and
observation identity come from the same stable read. Direct observation commands
remain addressable by explicit path; ignore rules affect scan-derived workspace
inventories, including `check` and Agent graph queries.

The built-in `workspace-file` observation-provider capability is version `"3"`.
Version 3 includes the ignore-aware inventory contract and fixes observation
types before interpreter selection.

## Content Identity

Regular-file content is read in bounded chunks. SHA-256 state and byte length
are accumulated incrementally, so memory consumption does not grow with the
observation size. The resulting pair is emitted as `ContentIdentity`.

The scan result does not retain file contents. The provider assigns
`text/markdown@1` to `.md` and `.markdown`, `application/yaml@1` to `.yaml` and
`.yml`, and `application/x-ndjson@1` to `.jsonl` and `.ndjson`. Unknown suffixes
receive `application/octet-stream@1`. An explicitly supplied extension file
association may assign one declared type to a matching unknown suffix before a
workspace graph is built. The interpreter receives that same fixed observation;
it does not reclassify it.

Every file has a content-derived observation identity. Its `contentIdentity` is
also emitted for byte-range validation and filesystem change detection.

Content identities cover the bytes present in the workspace; scan does not
normalize line endings. Repository fixtures and goldens therefore have an
explicit LF checkout policy in `.gitattributes`, including on Windows. This
policy fixes test inputs and does not change files in a scanned user workspace.

## Ordering and Failure Results

Directory entries are sorted before recursive traversal, and observable
observation and diagnostic collections are normalized again before JSON encoding.
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
Observation reads used by inspect, resolve, check, and derive apply the same
rule: each retry repeats safe relative path resolution and opens a fresh
descriptor. In particular, they do not seek and reuse a handle after an
unstable Windows read.

This is not an atomic workspace snapshot: unrelated entries can still change
between their individual reads. Windows now traverses with retained directory
handles, enumerates from those handles, opens descendants relative to them, and
classifies reparse points as unsupported entries. Directory enumeration uses
the already-authorized retained handle without reopening the directory by path
or requesting a second access grant. The configured Windows CI job exercises
both inventory scanning and stable observation reads.

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

Portable ignore tests cover root and nested precedence, negation, anchored and
directory-only patterns, single- and double-star behavior, escaped prefixes and
spaces, bracket classes, `.monikaignore` overrides, built-in `.git` exclusion,
and ignore-file symlinks that must not become configuration.

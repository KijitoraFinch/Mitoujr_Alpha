# CLI Contract Notes

The initial CLI family is:

- `monika scan`
- `monika inspect`
- `monika resolve`
- `monika check`
- `monika derive`
- `monika apply`
- `monika capabilities`
- `monika extension test`

The Agent-facing query family is separate from the normalized command-result
protocol:

- `monika related`
- `monika read`

`related` emits an Agent-readable text result by default and a compact,
query-specific JSON result with `--json`. `read` emits an Agent-readable
observation view; callers use `inspect` when they need normalized JSON. Neither
text command emits a version 7 `CommandResult`. Their graph, coverage, and
rendering boundaries are fixed in [agent-query-api.md](agent-query-api.md).

The installation identity interface is:

- `monika --version`

`--version` emits one whitespace-free human-readable implementation identity
for installation reports. A binary release emits
`<semver>+<12-character-commit-prefix>`; source and development identities
remain distinguishable. The reporting boundary is fixed in
[codex-reporting.md](codex-reporting.md).

The current JSON result envelope uses schema version `"7"`. Version 6 added
extension origins, schema-named extension selectors, interpreter versions, and
interpreter-free whole regions. Version 7 removes the former content-only
wrapper and exposes `Observation` directly as `id`, `origin`, and `identity`,
with optional `contentIdentity`. It also uses observation-scoped IDs, `origin`
in region addresses, and `changedFiles` for filesystem effects. No older wire
shape is accepted by the version 7 decoder.

Every result contains `diagnostics`, `patches`, `changedFiles`, `conflicts`,
`snapshots`, `observations`, `regions`, `references`, `annotations`, and
`capabilities` arrays, including when they are empty. `summary` is omitted when no summary was
generated; an empty object means a summary was generated with no entries.
Optional fields are omitted and are not encoded as `null`.

Paths are workspace-relative, slash-separated, and percent-encoded by byte.
Collections are sorted by semantic canonical keys before encoding.

Every region target carries an explicit selector. Use
`{ "kind": "whole-observation" }` for an entire observation. Do not encode an entire
observation by omitting `selector`, and do not normalize a full byte range into
`whole-observation`.

`status` and `exitClass` are derived from command termination, effect, and
effective diagnostic severity. The process exit code is a stable projection of
`exitClass`: `success` is 0, `diagnostic-error` is 1, `usage-error` is 2, and
`internal-error` is 3. The JSON result is still written to stdout for every exit
class; stderr is not the result channel.

An exception that reaches the command-dispatch boundary is converted to an
`internal-error` `CommandResult` with `errorCode: "unhandled-exception"` and
`operation: "command-dispatch"`. The exception text, native path, and stack
trace are not exposed as protocol fields. This boundary also covers unexpected
exceptions while serving the Agent-facing text commands; their documented
usage and diagnostic failures continue to use their query-specific channels,
but an implementation defect cannot terminate without a structured result.

The command result payload is constrained by `effect`. `No_change` has no
patches, changed files, or conflicts. `Patches_proposed` has non-empty
patches and no changed files or conflicts. `Applied` has non-empty changed
files and no patches or conflicts. `Conflicted` has non-empty conflicts and
no patches or changed files.

`observations` is an observation collection, not an effect payload. Commands such
as `scan` may return observations with `No_change`; patching commands may leave it
empty.

## `monika capabilities`

```sh
monika capabilities
```

The command accepts no arguments. It returns the built-in capability objects
known to this executable in canonical `(type, name, version)` order. Each
object fixes its type, name, version, optional applicability, and optional
schema references. It does not probe the workspace or load external code.

## `monika extension test`

```sh
monika extension test --manifest <file>
monika extension test --manifest <file> \
  --executable <file> [--argument <value>]...
```

`--manifest` is required and occurs at most once. The current test strictly
validates one declarative protocol version 1 manifest and returns its
capability observation. When `--executable` is present, the command starts that
process without a shell, passes every repeated `--argument` in source order,
calls `monika.initializeSession` over stdio JSON-RPC, compares the returned
protocol version and capability with the manifest,
and requires a clean process exit after stdin reaches EOF. `--argument` is
invalid without `--executable`.

The runtime check covers process transport and `monika.initializeSession`. `inspect` can
dispatch `monika.interpretObservation` to an explicitly provided temporary interpreter
extension. `resolve` can use the same temporary extension for
`monika.interpretObservation` followed by `monika.resolveRegion` in one checked session. The
exact transport contract is fixed in [extension-protocol.md](extension-protocol.md).

## `monika inspect`

The first inspect input contract is:

```sh
monika inspect --workspace <dir> --observation <canonical-workspace-path>
monika inspect --workspace <dir> --observation <canonical-workspace-path> \
  --extension-manifest <file> \
  --extension-executable <file> [--extension-argument <value>]...
```

`--workspace` and `--observation` are required and occur at most once. `--workspace`
selects the native workspace root; `--observation` is a canonical
workspace-relative path and does not accept a second native path syntax. The
first interpreter slice uses workspace observations. Other origin kinds remain
representable in extracted addresses but require an explicit future CLI input
form.

`--extension-manifest` and `--extension-executable` are optional, but when one
is present both must be present. `--extension-argument` is invalid without
`--extension-executable` and is passed to the executable in source order. This is
a temporary registration for the current command only; it does not write
workspace configuration. The manifest capability must be an `interpreter`.
The selected observation must satisfy the manifest applicability rules.
Known suffixes provide a fixed media type; an unknown suffix requires a matching
path glob and a single declared media type. An invalid or inapplicable manifest
is a usage failure, not permission to invoke the extension anyway.

Inspect extracts explicit observations and returns the selected observation plus
its `regions`, `references`, and `annotations`. It does not resolve references
and does not infer absent relations. A target that has not been resolved remains
a `RegionAddress` containing origin, selector, and optional interpreter. A
resolved target is a scoped region ID. Region, reference, and annotation IDs are
observation-scoped `{ "observation", "local" }` objects and use distinct semantic
types; equal local values in different observations are different IDs.

When an address identifies an interpreter, `interpreter` and
`interpreterVersion` are both required. Neither the decoder nor the semantic
constructor supplies a version implicitly.

When an extension is provided, inspect starts the process without a shell,
performs `monika.initializeSession`, calls `monika.interpretObservation`, fills omitted non-whole
region interpreter fields from the manifest, and returns the extension
capability in the result's `capabilities` collection. Extension runtime failures
and invalid extension interpretation results are usage failures for this explicit
ad hoc invocation.

## `monika resolve`

```sh
monika resolve --workspace <dir> --observation <canonical-workspace-path> \
  --reference <local-reference-id> --observed-at <canonical-RFC3339-UTC>
monika resolve --workspace <dir> --observation <canonical-workspace-path> \
  --reference <local-reference-id> --observed-at <canonical-RFC3339-UTC> \
  --extension-manifest <file> \
  --extension-executable <file> [--extension-argument <value>]...
```

The four base options are required and occur at most once. The explicit
observation time prevents hidden wall-clock nondeterminism. Snapshot and
selector behavior are fixed in [resolve-snapshot.md](resolve-snapshot.md).

The extension options have the same pairing and argument-order rules as
`inspect`. When present, `resolve` starts one checked interpreter session,
observes the source observation, selects the named reference from that observation,
reads its workspace target through the stable filesystem boundary, and resolves
the target selector in the same session. Both source and target paths must
satisfy the manifest applicability. The reference target's interpreter
name and version must equal the manifest capability. An extension selector's
schema must equal `capability.schemas.selector`.

The returned region must belong to the exact target observation, use the
requested selector and manifest interpreter, and stay within the target byte
length. A malformed response or explicit runtime mismatch is a usage failure.
An extension `invalid-selector` failure becomes an `invalid-selector`
diagnostic; other semantic resolution failures become `unresolved-ref` while
retaining the extension failure code in the message. The current ad hoc path
supports workspace targets and one interpreter for both source observation and
target resolution. Installed extension selection and cross-interpreter dispatch
remain future registry work.

## `monika check`

```sh
monika check --workspace <dir>
```

`--workspace` is required and occurs at most once. Check scans safely readable
workspace observations, extracts observations using available standard
interpreters, resolves supported selectors, and emits diagnostics without
patches or writes. Error-severity findings produce process exit code 1. The
initial audit and JSONL selector rules are fixed in
[check-auditing.md](check-auditing.md).

## `monika derive`

```sh
monika derive --workspace <dir> --observation <canonical-workspace-path> --target sidecar
```

All options are required and occur at most once; the initial target enum accepts
only `sidecar`. Derive returns patches and never writes the workspace. The first
inline-to-sidecar rules and idempotency contract are fixed in
[derive-sidecar.md](derive-sidecar.md).

## `monika scan`

The first executable CLI contract for scan is intentionally small:

```sh
monika scan --workspace <dir>
```

`--workspace <dir>` identifies the workspace root to enumerate. Scan recursively
lists existing regular files under that root, computes each file's
`ContentIdentity`, and emits workspace observation descriptors in the command
result's `observations` array. Observation origins use canonical workspace-relative
paths.

Scan automatically applies `.gitignore` and `.monikaignore` files from each
visited directory. `.monikaignore` uses the same pattern form and has higher
precedence at the same directory level, so it can add Monika-specific exclusions
or negate a `.gitignore` rule. Deeper files override inherited rules. Monika
does not consult the Git index, `.git/info/exclude`, or user-level Git
configuration, and always excludes `.git` metadata.

Directories are traversal structure and are not observations. Symlinks and other
non-regular filesystem entries are not followed in this slice; scan reports
them as `unsupported-filesystem-entry` diagnostics. CLI parse errors and invalid
workspace roots produce `invalid-input`. An I/O failure that prevents a complete
inventory
produces `internal-error`; scan does not return a successful partial inventory.
The detailed boundary and its current concurrency limit are recorded in
[scan-filesystem-boundary.md](scan-filesystem-boundary.md).

## `monika apply`

The first executable CLI contract for apply is intentionally small:

```sh
monika apply --workspace <dir> --patch <file> --dry-run
monika apply --workspace <dir> --patch <file>
monika apply --workspace <dir> --result <command-result.json>
monika apply --workspace <dir> --result <command-result.json> \
  --patch-id <patch-id>
```

`--workspace <dir>` identifies the workspace root used to resolve patch targets.
Exactly one of `--patch` and `--result` is required. `--patch <file>` contains
one `ProposedPatch` JSON object in the same observable shape emitted by
`Normal_json.patch`. `--result <file>` reads the result's `patches` collection.
Its sole patch is selected automatically; multiple patches require an exact
`--patch-id`.

Workspace containment and target resolution are platform-specific filesystem
operations, not string-prefix checks. If the target cannot be mapped safely to a
native path under the workspace root on the current platform, apply returns
`invalid-input` or a filesystem safety failure; it must not silently rewrite a
different native path. Filesystem safety failures are returned as `conflict`
results with `kind: "filesystem-safety"` and a stable `reason` enum.

The patch file is not a command result and does not carry its own
`schemaVersion` field in this milestone. It contains:

- `id`
- `target`
- `operation`
- `resultingContentIdentity`
- `reason`
- `provenance`

An edit also contains `expectedContentIdentity` and a non-empty `edits` array.
A create instead contains complete UTF-8 `content`. Fields from the other
operation are rejected.

Patch JSON decoding is strict. Missing fields, unknown fields, `null`, type
mismatches, invalid workspace paths, invalid content identities, invalid ranges,
empty edit lists, empty reasons, and empty provenance sources are invalid input.

Without `--dry-run`, an edit reads the target file, checks the expected content
identity, applies text edits, verifies the resulting content identity, and then
writes the replacement through the filesystem boundary. A create verifies its
complete content identity and publishes it only if the target is absent. A
successful write returns an `applied` result with `changedFiles`; creation
omits the nonexistent `before` identity. If the current content already matches
`resultingContentIdentity`, apply returns an `ok` result and does not write the
file.

With `--dry-run`, apply performs the same decoding, workspace-root validation,
target safety checks, expected identity check, edit application, and resulting
identity verification, but it does not write. If the patch would apply, the
result is `patches-proposed` and contains the input patch. If the target already
has the resulting content, the result is `ok`. If a conflict is found, the
result is `conflict`, as in non-dry-run apply.

CLI parse errors, patch decode errors, and invalid workspace roots produce
`invalid-input`. Patch conflicts produce `conflict`. Their process exit codes
follow the `exitClass` mapping above.

An apply I/O failure produces `internal-error` with a stable summary. The
summary contains `errorCode`, `operation`, and the canonical workspace-relative
`location`; it may also contain `commitState`. `commitState` is
`not-committed` only when the boundary proves that replacement did not happen,
and `committed-or-unknown` when replacement happened or its visibility cannot
be proved. Native absolute paths, localized `strerror` text, and exception
renderings are not command-result fields.

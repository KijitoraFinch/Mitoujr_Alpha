# Schema Notes

`related-result.schema.json` is intentionally not a `CommandResult` schema. It
versions the compact Agent query result independently, while reusing the
canonical Origin, Selector, scoped ID, range, and path definitions from
`command-result.schema.json`. Version 6 carries endpoint resolution on typed
Reference and Relation edges, the complete coverage counters, explicit status,
normalized diagnostics, and truncation claims without adding unrelated effect
collections from `CommandResult`.

`report-bundle-manifest.schema.json` independently versions two closed integrity
manifests. Version `"1"` fixes the confidential Codex diagnostic bundle and its
complete-line capture boundary. Version `"content-1"` fixes chat-free proposal,
issue, complaint, and feedback bundles. Both fix the private GitHub destination,
required entries, safe byte-count domain, and lowercase SHA-256 representation.
The bundled Codex JSONL remains raw and has no Monika-owned record schema.

`release-manifest.schema.json` fixes the closed binary-release identity and
asset inventory. It binds one SemVer tag and full Git commit to byte counts,
lowercase SHA-256 values, platforms, and architectures.
`skill-package-manifest.schema.json` independently fixes the exact ordered file
inventory inside the OS-independent Skill archive. The executable release tool
also rejects duplicate ZIP entries, unsafe paths, symbolic links, and content
identities that differ from that manifest. Neither distribution manifest is a
`CommandResult`; their schema versions evolve independently from the CLI
protocol.

`sidecar-v2.schema.json` fixes the explicit root `scope.origin` and the
`authored` and `derived` ownership sections. YAML parser-level restrictions such as block versus flow
style, duplicate keys, aliases, anchors, and tags are enforced by the
executable decoder because JSON Schema does not observe YAML presentation.

`schemas/command-result.schema.json` defines the Phase 1 observable result and
its reusable diagnostic, patch, snapshot, observation, region, reference,
annotation, capability, path, range, identity, and conflict definitions. The standalone
schemas reference those definitions so that their contracts cannot drift
through duplication. `region-address.schema.json` is the standalone input
contract accepted by `monika resolve --address`.

`schemas/interpretation.schema.json` defines the closed result of interpreting
one already fixed observation. It contains the exact Interpreter identity, the
input Observation ID, and Regions only. Reference and Annotation extraction are
independent capability results.

`annotation-extraction.schema.json` and
`reference-extraction.schema.json` fix those independent results.
`workspace-graph-snapshot.schema.json` version 2 fixes the immutable graph value
consumed by Auditors and Derivers. Relation endpoints are closed to RegionRef;
Reference-valued Annotation objects are resolved to their consistent target
RegionAddress before encoding. `audit-policy.schema.json` and
`derive-request.schema.json` fix their declarative operation inputs. A
DeriveRequest contains exactly one tagged Annotation or Reference definition
occurrence, rather than an Origin-wide implicit selection.
`diagnostic-list.schema.json` and `proposed-patch-list.schema.json` fix the
corresponding extension results without wrapping them in a `CommandResult`.

`schemas/extension-manifest.schema.json` fixes the closed protocol version 1
static Extension manifest and reuses the command-result capability definition.
Every capability declares exact `acceptedObservationTypes`,
`applicability.pathGlobs`, `selectorSchemas`, and a non-empty `resultSchemas`
list. The runtime executes Resource Observer, Interpreter, Annotation Extractor,
Reference Extractor, Auditor, Deriver, Region resolution, and Region extent
roles through separate dispatchers and method contracts.
The OCaml decoder independently constructs the same semantic capability through
its validated constructor; schema validation is not used as a substitute for
the executable input boundary.

`extension-runtime-initialize-session.schema.json` defines the JSON-RPC request,
success response, and error response used by `monika.initializeSession`. The runtime decoder
also rejects duplicate fields, invalid UTF-8, floating-point values, unsafe
integers, unknown fields, and response-ID mismatches because JSON Schema alone
does not provide the complete process boundary.

`extension-registry.schema.json` defines an immutable snapshot of host installation
state. Each entry pairs one declarative manifest with an absolute executable path
and argument array plus a closed authority value. Schema version 2 distinguishes
ordinary sandboxed launch paths from Resource Observer read/network authority.
The OCaml decoder additionally rejects duplicate capability identities and
capability/authority mismatches.

`extension-runtime-methods.schema.json` defines the JSON-RPC messages for
`monika.interpretObservation`, `monika.extractReferences`,
`monika.resolveRegion`, `monika.classifyRegionExtents`,
`monika.extractAnnotations`, `monika.observeResource`, `monika.audit`, and
`monika.derive`, together with byte-stream notifications in both directions.
The schema reuses the command-result Observation, Region,
reference, selector, and content identity definitions so that extension results
and normalized command results cannot drift.

The current command-result schema version is the string `"11"`. Version 6 added
extension origins, schema-named extension selectors, interpreter versions, and
whole regions without interpreters. Version 7 exposes the general Observation
shape directly: identity is type-qualified, content identity is optional,
scoped IDs name their observation, region addresses contain `origin`, and
filesystem effects use `changedFiles`. Version 8 adds structured Extension
failure details to diagnostics: operation, extension-specific code, and optional
normalized protocol data remain separate from the human-readable message.
Version 9 added the mandatory Observation representation and gave extension
Origins an exact Resource Observer identity with a normalized locator. Version
10 separates Annotation occurrences, Reference definition occurrences, and
Reference uses; exposes fixed Sidecar snapshots and complete coverage; and
uses Origin-scoped identifiers throughout. Version 11 adds four closed
Observation expectation variants, schema-named Region fingerprints, a singular
RegionAddress expectation, and the `resolution-changed` warning code.
Required collections are never omitted.
Optional values are represented by field omission unless a field explicitly
defines another meaning. Schema-defined extension selector values may contain
JSON `null`; protocol-owned optional fields do not use `null`. The
versioning rules are recorded in
[schema-versioning.md](schema-versioning.md).

The OCaml representative fixture is encoded by `Normal_json` and validated
against the schema by `tools/check_golden.py`. The checker also mutates boundary
cases to ensure missing collections, `null`, cross-operation patch fields, and
empty edit lists are rejected. Its snapshot contains the same
`row-filter.where` shape used by the
basic sidecar fixture, so the encoder and selector schema are checked together.
The scan golden is generated by `monika scan --workspace fixtures/basic` and
validated against the same command-result schema.

JSON Schema provides the structural layer. The standalone
`tools/semantic_contract.py` validator applies checks that Draft 2020-12 cannot
express directly, including `range.end >= range.start` and the payload
invariants of each conflict kind, validates create content identities, requires
unique patch IDs, and rejects integral values written with JSON float syntax.
The golden checker imports this same validator. All specification JSON is
parsed with duplicate-key and non-finite-number
rejection. Generated output is compared with JSON types and normalized object
member order preserved; Python's coercive `1 == 1.0 == true` equality is not
used as an oracle.

All protocol integers use the interoperable JSON safe-integer domain
`[-9007199254740991, 9007199254740991]`. Byte sizes, byte offsets, text ranges,
content lengths, and summary counts additionally require non-negative values.
Row-filter integer literals may be negative. Sugar constructors enforce the
same limits before a value can reach the normal-form encoder, and schemas carry
explicit bounds on every integer position.

Every schema-visible string is Unicode scalar text encoded as UTF-8. Sugar
constructors reject invalid UTF-8 before normal-form encoding, and the strict
specification JSON loader rejects lone surrogate values before schema
validation. `TextEdit.replacement` is text and follows this rule. Arbitrary-byte
replacement is not represented by overloading a JSON string; adding it requires
a separately tagged base64 or hexadecimal payload variant and a schema-version
review. Sugar, the specification validator, and Bitter consume the same UTF-8
byte corpus for overlong, surrogate, truncated, boundary-scalar, and valid
multibyte cases.

Observation and patch identifiers retain their string wire shape,
but Sugar no longer represents them with one interchangeable identifier type.
`Observation_id.t` is workspace-global within an observation result, while
`Patch_id.t` is command-scoped; both are abstract and cannot be passed where the
other is required. Version 3 represents region, reference, and annotation IDs
as distinct abstract OCaml types and `{ "observation", "local" }` objects. The
observation participates in identity, so equal local names in different observations
do not collide. Delimiter-concatenated IDs are not accepted as a substitute.

Conflict schema definitions mirror the OCaml algebraic data type with `oneOf`.
Each conflict kind has its own required detail fields and rejects fields from
other variants. `Conflict.t` is a private variant: consumers may pattern-match
on it but must use validated constructors. Identity mismatch constructors
require unequal identities, range-out-of-bounds requires a range beyond the
declared content length, and overlapping-edits requires intersecting ranges.

The command-result schema also constrains `status` and payload collections
together. For example, `ok` cannot carry patches, changed files, or
conflicts; `applied` requires changed files and rejects patches and
conflicts; `conflict` requires conflicts and rejects patches and changed
files. The `observations` collection is independent of the effect payload and
may be non-empty for read-only commands such as `scan`.

Path strings follow `Workspace_path.to_canonical_string`, not a looser
percent-escaped path syntax. Percent escapes use uppercase hex and are only used
for bytes that are not unreserved path characters. Encoded slash, NUL, encoded
unreserved characters, lowercase escapes, empty segments, and literal dot or
dot-dot segments are rejected. Workspace paths are ordered lexically by this
canonical string, not by the host platform's raw filename bytes.

`row-filter.where` is the observable projection of the OCaml
`Selector.Row_filter` abstract map. It is a non-empty JSON object with non-empty
property names and exact string, integer, or boolean literals. Floating-point
numbers and `null` are not part of the current semantic model. Object keys are
emitted in canonical lexical order. The selected interpreter owns the meaning
of applying those conditions to an observation.

Resolution targets require a selector. The canonical selector for an entire
observation is `{ "kind": "whole-observation" }`. A byte range covering the current
file size is not equivalent to `whole-observation`; it remains a fixed byte-range
selector. Future structural addressing modes should extend the selector union
rather than rely on omitted selectors.

The region, reference, and annotation standalone schemas expose the version 11
shapes. `RegionAddress` preserves an unresolved origin, selector, and optional
address expectation. A whole-observation address omits Interpreter identity;
every partial address requires the exact Interpreter name and version. Region
values use the same Whole-versus-partial rule; Extension results cannot rely on
the receiving manifest to add a missing identity. `Region_ref`
distinguishes that address from a resolved scoped ID. Reference expectations use
the closed `Expectation` algebra. Its variants carry an ObservationIdentity, a
complete ContentIdentity, a schema-named revision, or a schema-named Region
fingerprint. Pinned References require at least one address or Reference
expectation; Tracking and Floating References have no Reference-level pinned
expectations. Sidecar v2 uses the same four variants without the normalized
`kind` discriminator: the single member name identifies the variant.

Capability objects are closed objects with a stable identity consisting of
`type`, `name`, and `version`. Exact accepted Observation types and
applicability path globs are separate required values. Selector schema lists
may be empty, while result schema lists are non-empty. All collections are
duplicate-free. The semantic validator rejects duplicate capability
identities and path globs outside the protocol grammar, matching the OCaml
constructors. Applicability evaluation is semantic because matching a canonical
workspace path and detecting ambiguous ObservationType associations cannot be fixed
by the manifest schema alone.

The first JSON input decoder is `Normal_decode.proposed_patch`, used by
`monika apply`. It accepts the same patch object shape that `Normal_json` emits
inside command results, but it is not part of `Normal_json`: output encoding and
input validation have different responsibilities. The decoder is strict about
required fields, unknown fields, `null`, type mismatches, and fields from the
wrong create/edit variant, and it constructs semantic values through the same
constructors used by the OCaml model tests.

Filesystem safety failures observed by apply are represented as
`filesystem-safety` conflicts with a stable `reason` enum. They are conflicts,
not successful no-op results, because they describe a target that apply refused
to write safely.

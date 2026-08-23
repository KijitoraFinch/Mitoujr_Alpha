# Fixtures

The first fixture corpus is `fixtures/basic/`. Commands that execute this corpus
use that directory as the workspace root, so every workspace origin stored in
the fixture is relative to `fixtures/basic/` (for example,
`runs/metrics.jsonl`, not `fixtures/basic/runs/metrics.jsonl`).

It is intentionally small and records important cases covered by the current
implementation or reserved for later interpreter slices:

- Markdown inline link
- sidecar-only annotation
- inline-only annotation
- divergent annotation
- stale selector
- unreferenced reference
- unresolved reference
- source comment annotation
- JSONL pinned reference

The real inspect, check, and derive CLI goldens now bind the Markdown, sidecar,
JSONL, six diagnostic cases, and inline-to-sidecar patch to concrete outputs.
Source comment extraction remains a later interpreter slice.

`fixtures/ignore/` fixes automatic `.gitignore` loading, the higher-priority
`.monikaignore` override surface, nested rule precedence, negation, and
directory-pruning behavior. Its excluded files are intentionally present in the
fixture but absent from `golden/scan/ignore.expected.json`.

`fixtures/extensions/` contains manifest and runtime protocol inputs as well
as `resolve-workspace/`, a workspace fixture whose source and target observations
exercise same-session extension resolution. The valid manifest drives the
real `monika extension test` golden; the unsupported-version manifest fixes
version-negotiation rejection.

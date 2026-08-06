# Fixtures

The first fixture corpus is `fixtures/basic/`. Commands that execute this corpus
use that directory as the workspace root, so every workspace origin stored in
the fixture is relative to `fixtures/basic/` (for example,
`runs/metrics.jsonl`, not `fixtures/basic/runs/metrics.jsonl`).

It is intentionally small but records the important cases that later phases must
make executable:

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

`fixtures/extensions/` contains protocol inputs rather than workspace
artifacts. Its valid descriptor drives the real `monika extension test` golden;
the unsupported-version descriptor fixes version-negotiation rejection.

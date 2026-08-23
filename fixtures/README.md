# Fixtures

Fixtures are source inputs for the reference implementation and later
cross-implementation tests.

`fixtures/basic/` is the first corpus. It is deliberately small and focused on
cases that exercise the core model. The corpus directory is its workspace root;
workspace paths inside fixture data are relative to that directory.

`fixtures/extensions/valid-manifest.json` and
`fixtures/extensions/valid-runtime.py` are inputs to the extension contract
checks. The Python process reads one JSON-RPC request per line, responds to
`monika.initializeSession`, `monika.interpretObservation`, and
`monika.resolveRegion`, flushes each
response, and exits after stdin reaches EOF.
`fixtures/extensions/resolve-workspace/` fixes the ad hoc interpreter sequence
that observes a source reference and resolves its target region in one checked
extension session.
`fixtures/extensions/related-manifest.json`, `related-runtime.py`, and
`related-workspace/` fix applicability-based dispatch across a workspace and an
incoming relation emitted by an explicitly supplied interpreter extension.

`fixtures/ignore/keep.generated` is intentionally force-tracked even though the
fixture's `.gitignore` matches it. Its `.monikaignore` rule re-includes the file
to verify that Monika applies the two ignore files in order without consulting
the Git index.

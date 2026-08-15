# Fixtures

Fixtures are source inputs for the reference implementation and later
cross-implementation tests.

`fixtures/basic/` is the first corpus. It is deliberately small and focused on
cases that exercise the core model. The corpus directory is its workspace root;
workspace paths inside fixture data are relative to that directory.

`fixtures/extensions/valid-descriptor.json` and
`fixtures/extensions/valid-runtime.py` are inputs to the extension contract
checks. The Python process reads one JSON-RPC request per line, responds to
`monika.describe`, `monika.observe`, and `monika.resolveRegion`, flushes each
response, and exits after stdin reaches EOF.
`fixtures/extensions/resolve-workspace/` fixes the ad hoc interpreter sequence
that observes a source reference and resolves its target region in one checked
extension session.

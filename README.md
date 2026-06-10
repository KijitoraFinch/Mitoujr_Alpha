# Alpha

Alpha is the working repository for Monika, a foundation for treating documents,
source code, logs, experimental data, web captures, and unknown blobs as
interpretable artifacts.

The current repository state is Phase 0: development infrastructure before the
data model is detailed. The scaffold intentionally fixes directories, fixture
locations, validation commands, and build boundaries without pretending that the
final schema fields are already settled.

## Phase 0 Checks

```sh
make phase0-check
make golden-check
make build-sugar
make check-bitter
```

`make check` runs all checks.

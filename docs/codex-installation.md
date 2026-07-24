# Codex Installation Guide

This guide installs the Sugar OCaml reference implementation and the `monika`
CLI from a source checkout. The first pre-alpha distribution is intended for an
internal group whose members have Codex available, so the normal entry point is
the copyable request at the end of this document.

The commands below describe the repository's build structure precisely. Codex
may select equivalent platform-specific package-manager commands when preparing
the toolchain.

## Source Layout

- `sugar/` contains the installable OCaml library and `monika` executable.
- `schemas/`, `spec/`, `fixtures/`, and `golden/` contain the observable
  contracts and their test data.
- `tools/` contains repository, schema, golden, and distribution checks.
- `bitter/` is the later Rust implementation scaffold. Rust is needed for the
  complete repository check, but not to install the Sugar executable.

When identifying a distribution, use the Git commit ID. For an unpacked archive
without Git metadata, use the SHA-256 digest supplied with that archive.

## Toolchain

The reference configuration uses:

- Python 3.13;
- opam;
- OCaml 5.2 or later;
- Dune 3.10 or later;
- a C compiler supported by Dune;
- the Python packages pinned in `tools/requirements-ci.txt`.

The OCaml package dependencies are declared in `sugar/dune-project` and the
generated `sugar/monika_sugar.opam`. They include Cmarkit, Ptime, YAML, Yojson,
Digestif, Alcotest, and QCheck-Alcotest.

Rust with `rustfmt` and `clippy` is additionally required when running the full
`make check` target.

## Prepare an OCaml Environment

An opam switch using OCaml 5.2 or later is required. A repository-local switch
is convenient for an internal source installation:

```sh
opam switch create . 5.2.1
eval "$(opam env)"
```

If a suitable switch already exists, select it instead. Install the Sugar
dependencies, including test dependencies:

```sh
opam install ./sugar --deps-only --with-test
```

Install the Python contract-checking dependencies into the selected Python
environment:

```sh
python3 -m pip install --requirement tools/requirements-ci.txt
```

## Build and Test

Run the repository-independent Python checks first:

```sh
python3 tools/check_phase0.py
python3 tools/test_json_contract.py
python3 tools/test_semantic_contract.py
```

Build and test Sugar:

```sh
dune build --root sugar @install
dune runtest --root sugar
```

Validate the schemas, normal forms, CLI goldens, filesystem transitions, and
derive/apply/derive idempotency:

```sh
python3 tools/check_golden.py
```

Finally, build Sugar in isolated Dune package mode, install it into a temporary
prefix, inspect the installed file set, and execute the installed CLI:

```sh
python3 tools/check_distribution.py
```

For a complete producer-side repository check, including Bitter:

```sh
make check
```

When Dune and the OCaml dependencies exist only in the selected opam switch,
run the command through that environment:

```sh
opam exec -- make check
```

## Install the CLI

Install the local Sugar package into the selected opam switch:

```sh
opam install ./sugar --with-test
```

Locate and execute the installed command:

```sh
command -v monika
monika capabilities
```

`monika capabilities` must return a schema version 4 command result with the
built-in workspace provider, Markdown, sidecar, and JSONL interpreters,
annotation extractors, deriver, and auditor.

A workspace smoke test can use the included fixture:

```sh
monika scan --workspace fixtures/basic
monika inspect --workspace fixtures/basic --artifact docs/linking.md
monika read --workspace fixtures/basic --artifact docs/linking.md
monika related --workspace fixtures/basic --artifact docs/linking.md
```

`inspect` returns the normalized artifact, region, reference, and annotation
observations. `read` renders the artifact directly for an Agent, while
`related` returns its explicit outgoing and incoming workspace relations.

## Generated Directories

The normal build and installation flow may create:

- `_opam/` for a repository-local opam switch;
- `sugar/_build/` for Dune build output;
- Python `__pycache__/` directories;
- `bitter/target/` when the Rust checks are run.

These are generated environments or build outputs and are excluded from Git.

## Copyable Codex Request

Replace `<SOURCE>` and `<REVISION>` before sharing the request. `<SOURCE>` may
be a repository URL, an existing checkout, or an unpacked source archive.

```text
Monika の内輪向け Pre alpha を、この環境にインストールしてください。

配布元:
- source: <SOURCE>
- revision または archive SHA-256: <REVISION>

このリポジトリの AGENTS.md を読んだうえで、
docs/codex-installation.md を Installation Guide として使用してください。

環境に合わせて必要な Python、opam、OCaml、Dune、および package dependency を
準備し、Sugar をビルドしてテストしてください。その後、Sugar package を
インストールし、インストールされた monika CLI で capabilities と
fixtures/basic に対する scan、inspect、read、related を実行してください。

途中で source code、schema、golden、build、test、または platform 固有処理の問題が
見つかった場合は、原因を調査し、配布元の不具合であれば修正案を示してください。

最後に、使用した source revision、OS、Python・OCaml・Dune・opam の version、
monika 実行ファイルの場所、実行した検証と結果をまとめてください。
```

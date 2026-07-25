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
- `skills/monika-update/` contains the verified source-update workflow.
- `skills/monika-report/` contains the problem-report workflow.
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
Digestif, Dune Build Info, Alcotest, and QCheck-Alcotest.

Rust with `rustfmt` and `clippy` is additionally required when running the full
`make check` target.

GitHub CLI (`gh`) is required only when submitting a bundle with the reporting
Skill; local report collection does not require GitHub access.

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
python3 tools/test_report_bundle.py
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
monika --version
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

## Install the Bundled Skills

Copy the complete `skills/monika-update/` and `skills/monika-report/`
directories into the active Codex skills directory with those same names. The
default parent is `$CODEX_HOME/skills`, or `~/.codex/skills` when `CODEX_HOME`
is unset.

Replace only those two exact managed Skill directories when updating them; do
not replace the surrounding `skills/` directory or unrelated user Skills.
Start a new Codex thread after installation so the Skills are discovered.

The update workflow and self-update ordering are defined in
[codex-update-skill.md](codex-update-skill.md). The reporting Skill can always
collect a local report bundle. Submission additionally requires `gh`
authenticated with access to the private
`MitouJr-2026/reports` repository and its `report-inbox` Release. The report
format and confidentiality boundary are defined in
[codex-reporting.md](codex-reporting.md).

## Update an Existing Installation

Treat the requested Git commit ID as the identity of an update. Retain the
revision reported when the existing installation was made; `monika --version`
also reports the VCS-derived identity when the installation retained that build
provenance.

Before updating, record the selected opam switch and executable path:

```sh
opam switch show
opam exec -- command -v monika
opam exec -- monika --version
opam pin list
```

Prepare a clean source tree at the requested revision. An existing checkout may
be updated when it has no local changes. If it contains local changes or
untracked files, preserve them and prepare the requested revision in a separate
clone or Git worktree instead. The verified `sugar/` directory becomes an opam
pin target and must remain available after the update; do not use a temporary
directory that is deleted when the current task ends. Keep the previous pin
target available until the new installation has passed verification.

Read `AGENTS.md` from the requested revision because its repository
instructions may have changed. Then prepare any newly required dependencies and
verify the checked-out commit with `git rev-parse HEAD`. Run the Python contract
checks, Sugar build and tests, golden validation, and distribution check from
this guide before replacing the installed package.

The package currently has no public release version, so a newer source revision
may still have the same opam package version as the installed revision. Point
the local pin at the verified `sugar/` directory and request an explicit
reinstallation:

```sh
opam pin add monika_sugar ./sugar --no-action
opam reinstall monika_sugar --with-test
```

Run the installed-CLI verification through the same switch:

```sh
opam exec -- command -v monika
opam exec -- monika --version
opam exec -- monika capabilities
opam exec -- monika scan --workspace fixtures/basic
opam exec -- monika inspect --workspace fixtures/basic --artifact docs/linking.md
opam exec -- monika read --workspace fixtures/basic --artifact docs/linking.md
opam exec -- monika related --workspace fixtures/basic --artifact docs/linking.md
```

An update is complete only after the requested source revision passes the
repository checks, the package has been explicitly reinstalled, and these
commands execute the installation selected by `opam exec`.

If reinstallation or installed-CLI verification fails, restore and reinstall
the recorded previous pin when its source is available, then verify the restored
CLI. Report the update and rollback results separately.

Update both bundled Skills from the same verified source revision after the CLI
verification. Replace `monika-report` first and `monika-update` last. Replace
whole Skill directories with restorable backups rather than copying over them;
preserve unrelated Skills. Confirm the installed file sets and use a new Codex
thread for the updated Skills.

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
インストールし、インストールされた monika CLI で --version、capabilities と
fixtures/basic に対する scan、inspect、read、related を実行してください。

skills/monika-update と skills/monika-report を、この環境で有効な Codex skills
directory に同じ名前でインストールしてください。周囲の skills directory や他の
Skill は変更しないでください。

途中で source code、schema、golden、build、test、または platform 固有処理の問題が
見つかった場合は、原因を調査し、配布元の不具合であれば修正案を示してください。

最後に、使用した source revision、OS、Python・OCaml・Dune・opam の version、
monika 実行ファイルの場所、実行した検証と結果をまとめてください。
```

## Copyable Codex Update Request

Replace `<SOURCE>` and `<REVISION>` before sharing the request.
`<PREVIOUS_REVISION>` is the revision recorded by the previous installation; if
that record is unavailable, write `unknown` rather than inferring it from the
current executable.

```text
この環境にインストールされている Monika の内輪向け Pre alpha を更新してください。

配布元:
- source: <SOURCE>
- previous revision: <PREVIOUS_REVISION>
- target revision: <REVISION>

target revision のリポジトリにある AGENTS.md を読んだうえで、
docs/codex-installation.md の「Update an Existing Installation」を使用してください。

最初に、現在選択されている opam switch と monika 実行ファイルの場所を記録してください。
既存の monika_sugar pin も記録してください。既存の checkout にローカル変更または
未追跡ファイルがある場合はそれらを保持し、別の clone または Git worktree に
target revision の清潔な source tree を用意してください。この source tree は更新後も
pin 先として保持し、一時 directory には置かないでください。旧 pin の source も
新しい installation の検証が終わるまで保持してください。

git rev-parse HEAD で checkout が target revision と一致することを確認してください。
target revision に必要な dependency を準備し、ガイドに記載された Python contract
check、Sugar の build と test、golden validation、distribution check を完了して
ください。その後、検証済みの sugar directory を monika_sugar の local pin として
設定し、同じ opam switch 上で package を明示的に再インストールしてください。

更新後は、その opam switch にインストールされた monika CLI で --version、
capabilities と
fixtures/basic に対する scan、inspect、read、related を実行してください。

途中で source code、schema、golden、build、test、または platform 固有処理の問題が
見つかった場合は原因を調査し、配布元の不具合であれば修正案を示してください。
package の再インストールまたは更新後のCLI検証に失敗した場合は、記録した旧 pin が
利用可能であれば復元して再インストールし、rollback 後のCLIも検証してください。

最後に、previous revision と target revision、OS、Python・OCaml・Dune・opam の
version、更新前後の monika 実行ファイルの場所、dependency の変更、実行した検証と
結果をまとめてください。また、検証済みの target revision に含まれる
skills/monika-report と skills/monika-update で、同名のインストール済み Skill
だけをこの順序で更新してください。周囲の skills directory や他の Skill は変更
しないでください。更新した Skill は新しい Codex thread から使用するものとして
案内してください。
```

## Copyable Codex Skill Update Request

Use this shorter request after `monika-update` has been installed. Replace the
optional target line only when a specific revision is required; otherwise the
Skill resolves the current `pre-alpha` channel to one exact commit.

```text
$monika-update を使用して、この環境の Monika を更新してください。
target revision: current pre-alpha

更新前後の identity、使用した source directory、opam switch、実行した検証、
CLI と2つの bundled Skill の更新結果、rollback の有無を報告してください。
```

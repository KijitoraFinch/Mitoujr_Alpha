# Codex Installation Guide

Monika は、公開済みの一つの GitHub Release から、対象環境用の単一 CLI バイナリを
per-user binary path へ配置する方法を推奨します。CLI の実行に OCaml、Dune、opam、
source checkout は必要ありません。Codex Skill は、別の OS 非依存 archive から
配置します。バイナリが提供されない target、独自変更、または再構築可能性の確認には、
この文書の後半にある source build を使用できます。

導入を Agent に任せる場合も、一つの release tag を最初に確定し、その release に
含まれる identity と checksum を最後まで使用してください。moving branch や
`latest` は release を発見するためだけに使用し、インストール済みの identity として
記録しません。

## Binary Release Contents

release version `<version>` には、次の閉じた file set が含まれます。

- `monika-<version>-linux-x86_64`
- `monika-<version>-macos-aarch64`
- `monika-<version>-macos-x86_64`
- `monika-<version>-windows-x86_64.exe`
- `monika-skills-<version>.zip`
- `release-manifest.json`
- `SHA256SUMS`

`release-manifest.json` は、release tag、SemVer、完全な Git commit ID、各 asset の
byte 数、SHA-256、platform、architecture を固定します。
`monika-skills-<version>.zip` 内の `manifest.json` は、三つの bundled Skill の
完全な file inventory と各 file の byte 数、SHA-256 を固定します。これらの
manifest は、それぞれ
`schemas/release-manifest.schema.json` と
`schemas/skill-package-manifest.schema.json` に従います。

現在の release artifact は署名されていません。`SHA256SUMS` は転送後の同一性を
検証しますが、別の配布元から取得した checksum を信頼できるものにはしません。
asset、manifest、checksum は、すべて同じ
`KijitoraFinch/Mitoujr_Alpha` GitHub Release から取得してください。

## Install a Binary Release

### 1. Resolve One Release

明示された tag がある場合は、その tag を使用します。現在の pre-alpha release を
要求された場合は、GitHub の公開済み non-draft release のうち、tag が
`v0.0.0-pre-alpha.<commit-timestamp>.g<12-character-commit-prefix>` に一致する
最新の release を一度だけ解決して、tag を記録します。GitHub の通常の
`latest release` は prerelease を返さないため、pre-alpha channel の解決には使用しません。
draft release や、同名の別 repository にある asset は使用しません。

release から `release-manifest.json` と `SHA256SUMS` を先に取得します。
manifest の `tag` が選択した tag と一致し、`version` が asset 名の version と一致し、
`commit` が完全な 40 文字の Git object ID であることを確認します。

### 2. Select and Verify the CLI

対象環境に対応する CLI asset を一つだけ選び、Skill archive とともに取得します。
OS と architecture は推測せず、ホストから観測した値を
`release-manifest.json` の `platform` と `architecture` に対応付けます。
対応する asset がない場合は、別 target のバイナリを試さず、
[Build from Source](#build-from-source) を使用します。

`SHA256SUMS` の対象 file 名を正確に照合し、CLI、Skill archive、
`release-manifest.json` の SHA-256 を検証します。さらに manifest 内の byte 数と
SHA-256 が同じ asset に一致することを確認します。検証前のバイナリは実行しません。

### 3. Place the CLI

新規の per-user installation では、次の場所を推奨します。

- macOS、Linux: `~/.local/bin/monika`
- Windows: `%LOCALAPPDATA%\Monika\bin\monika.exe`

親 directory を必要な範囲だけ作成し、CLI と同じ filesystem 上へ一時 file として
配置してから、最終名へ置き換えます。macOS と Linux では実行 permission を付けます。
選択した directory が `PATH` にない場合は、利用者の既存設定を保持したまま追加します。

既存の `monika` が opam switch、Homebrew、または別の package manager によって
管理されている場合、その管理下の file を直接上書きしません。上記の
binary-managed path に配置し、実際に選択される `monika` の path を確認します。
以前の package installation の削除は別の操作であり、暗黙には行いません。

配置後、完全 path を使用して次を実行します。

```sh
<installed-monika> --version
<installed-monika> capabilities
```

`--version` は `monika <version>+<12-character-commit-prefix>` を返し、version と
commit prefix は release manifest と一致しなければなりません。`capabilities` は
schema version 7 の `ok` result を返し、built-in workspace provider、Markdown、
sidecar、JSONL interpreter、annotation extractor、deriver、auditor を含む必要が
あります。

必要に応じて、一時 workspace に通常 file を一つ作成し、`scan`、`inspect`、
`read` がその workspace 外を必要とせずに動作することを確認します。一時 workspace
以外の利用者 file は変更しません。

### 4. Verify and Install the Bundled Skills

Skill archive を private temporary directory に展開します。展開先から直接 Skill を
実行しません。archive 内の root directory 名、`manifest.json`、三つの Skill の
file set が manifest の閉じた inventory と一致し、各 file の byte 数と SHA-256 が
一致することを確認します。絶対 path、`..`、重複 entry、symbolic link、manifest に
ない file を含む archive は拒否します。

active Codex skills directory は `$CODEX_HOME/skills`、`CODEX_HOME` が未設定の場合は
`~/.codex/skills` です。次の三つだけを同じ名前で配置します。

- `monika-report`
- `monika`
- `monika-update`

destination と同じ filesystem 上へ complete directory を stage します。既存の同名
Skill がある場合は、復元可能な backup を保持し、file を上書きコピーするのではなく
directory 全体を置き換えます。`monika-report`、`monika`、`monika-update` の順に
置き換え、途中で失敗した場合は三つとも以前の状態へ戻します。周囲の `skills`
directory や、他の Skill は変更しません。

配置後、三つの installed file set と manifest の identity をもう一度比較します。
更新済み Skill は現在の thread には再読み込みされないため、新しい Codex thread を
開始します。

`monika-report` は local bundle の収集には GitHub access を必要としません。
submission だけが、private `MitouJr-2026/reports` repository の `report-inbox`
Release への access と、別 turn での明示的な利用者確認を必要とします。

## Update an Existing Binary Installation

`monika-update` がインストール済みの場合は、更新処理をその Skill に任せます。
Skill 自身が、公開済み release の確定、現在状態の記録、同一性検証、CLI と Skill の
staging、置換順序、rollback、更新後検証を定義します。

手動更新でも、同じ規則を使用します。

1. 現在選択される CLI path、`--version`、三つの Skill file set を記録する。
2. target release を一度だけ解決し、全 asset を現在の installation の外へ取得する。
3. 新旧を変更する前に、release と Skill archive の全 identity を検証する。
4. CLI と三つの Skill を同じ filesystem 上へ stage し、rollback backup を作る。
5. CLI を置換し、完全 path で `--version` と `capabilities` を検証する。
6. `monika-report`、`monika`、`monika-update` の順に Skill directory を置換する。
7. どこかで失敗した場合は、CLI と三つの Skill を一組として以前の状態へ戻し、
   復元後の CLI を実行してから rollback 成功を報告する。

同じ release を再度指定した場合も、CLI と Skill の観測可能な identity を検証します。
すべて一致する場合は再配置を行わず、べき等な no-op として完了します。

## Build from Source

source build は、binary asset がない target、独自変更、特定 commit の検証、
または release の再構築に使用します。通常の binary installation には
OCaml toolchain は不要です。

### Requirements

参照構成は次のとおりです。

- Python 3.13
- opam
- OCaml 5.2 以降
- Dune 3.10 以降
- Dune が対応する C compiler
- `tools/requirements-ci.txt` に固定された Python package

OCaml dependency は `sugar/dune-project` と生成済みの
`sugar/monika_sugar.opam` に宣言されています。repository 全体の `make check` は
Bitter scaffold も検査するため、Rust、`rustfmt`、`clippy` も必要です。

### Resolve and Prepare the Source

Codex が source build、依存関係の調査、または source code の調査を行う場合は、
個別ファイルを読む前に、指定 revision の repository 全体を clone します。
`github.fetch` または同等の file API へ推測した path を片っ端から渡して、
repository 構成を探してはいけません。clone できない場合は推測による調査へ
切り替えず、source を取得できないことを報告します。個別 path の not-found 応答
から、dependency や manifest が存在しないと判断してはいけません。

完全な repository checkout を用意した後、`rg --files` などで構成を列挙します。
依存関係は、実在を確認した `sugar/dune-project`、
`sugar/monika_sugar.opam`、`tools/requirements-ci.txt`、
`bitter/Cargo.toml` などの宣言ファイルから確認します。

branch 名ではなく、完全な Git commit ID を一度だけ確定します。既存 checkout に
local change または untracked file がある場合は、それらを変更、削除、退避せず、
別の clone または Git worktree に target commit を準備します。

target checkout の `AGENTS.md` を読み、`git rev-parse HEAD` が target commit と一致し、
検証前の `git status --short` が空であることを確認します。

repository-local switch の例は次のとおりです。

```sh
opam switch create . 5.2.1
eval "$(opam env)"
opam install ./sugar --deps-only --with-test
python3 -m pip install --requirement tools/requirements-ci.txt
```

### Build and Verify

source build の identity として、完全な commit から得た先頭 12 文字を
`MONIKA_BUILD_IDENTITY=source-<12-character-commit-prefix>` に固定します。同じ値を
build、test、install の全工程へ渡します。値を設定しない開発用 build は
`monika unknown` となる場合があり、配布 identity には使用できません。

POSIX shell では、実際の prefix に置き換えて build 前に export します。

```sh
export MONIKA_BUILD_IDENTITY=source-<12-character-commit-prefix>
```

Windows では、Agent が利用中の shell に対応する同名の process environment variable
を設定します。identity に空白や改行を含めません。

repository-independent check と Sugar の build/test を実行します。

```sh
python3 tools/check_phase0.py
python3 tools/test_json_contract.py
python3 tools/test_semantic_contract.py
python3 tools/test_report_bundle.py
python3 tools/test_release_assets.py
dune build --root sugar @install
dune runtest --root sugar
python3 tools/check_golden.py
python3 tools/check_distribution.py
```

producer-side の完全検証には次を使用します。

```sh
opam exec -- make check
```

`tools/check_distribution.py` は、`sugar/` だけを独立した source tree へコピーし、
Dune package mode で build/test し、一時 prefix へ install して、installed CLI を
実行します。親 repository の undeclared runtime file に依存する build は拒否されます。

### Install the Source Build

検証に使用した同じ opam switch と build identity で package をインストールします。

```sh
opam install ./sugar --with-test
opam exec -- command -v monika
opam exec -- monika --version
opam exec -- monika capabilities
```

source checkout の `skills/monika-report`、`skills/monika`、
`skills/monika-update` は、binary release の Skill と同じ配置規則でインストールします。
source update のために opam pin を使用する場合は、pin target を一時 directory にせず、
previous target を rollback に必要な間は保持します。

通常の binary installation へ移行する場合、opam switch 内の実行ファイルを上書きせず、
binary-managed path を新設して、実際に選択される path を確認します。

## Producer Release Procedure

`pre-alpha` branch への push は binary release workflow を自動的に起動します。
workflow は commit timestamp と完全な commit ID から
`v0.0.0-pre-alpha.<commit-timestamp>.g<12-character-commit-prefix>` を決定的に生成し、
Linux x86-64、macOS arm64、macOS x86-64、Windows x86-64 の各 CLI を、その
release identity 付きで build/test します。各 CLI は build host 上で移設後に
`--version` と `capabilities` を実行します。

集約 job は決定的な Skill archive、release manifest、`SHA256SUMS` を生成し、閉じた
asset set を再検証してから、commit を指す immutable tag と公開済み
**prerelease** を作成します。build または検証に失敗した commit には tag も release も
作成しません。既存の tag または release は上書きしないため、同じ commit の再実行も
新しい配布 identity を作りません。

通常の release は、既存の immutable tag `v<semver>` を指定して workflow を手動実行
します。この経路は検証済み asset を **draft prerelease** として作成し、owner が
公開するまで利用者には配布しません。GitHub の制約により、手動実行には workflow が
default branch に存在する必要があります。

## Copyable Codex Requests

### Binary Installation

`<TAG>` を指定しない場合、Agent は最新の公開済み pre-alpha release tag を一度だけ
解決します。

```text
Monika を、この環境へ binary release からインストールしてください。

repository:
- https://github.com/KijitoraFinch/Mitoujr_Alpha
- release tag: <TAG または latest published pre-alpha release>

target release の docs/codex-installation.md に従ってください。同じ release から
release-manifest.json、SHA256SUMS、OS と architecture に対応する単一 CLI
バイナリ、Skill archive を取得し、実行または配置の前に identity と SHA-256 を
検証してください。

CLI は package manager 管理下の file を上書きせず、per-user binary path に
配置してください。Skill archive の manifest と全 file identity を検証し、
monika-report、monika、monika-update だけを active Codex skills directory に
配置してください。他の Skill は変更しないでください。

最後に release tag、version、commit、OS、architecture、CLI path、検証した
SHA-256、--version、capabilities、三つの Skill の配置結果を報告してください。
更新済み Skill は新しい Codex thread から使用するものとして案内してください。
```

### Source Installation

```text
Monika を source からビルドしてインストールしてください。

source: <repository URL または既存 checkout>
revision: <exact commit>

repository URL を指定した場合は、最初に完全な checkout を作成してください。
推測した file path への github.fetch を繰り返してはいけません。clone できない場合
は推測による調査へ切り替えず、停止して取得不能と報告してください。

target revision の AGENTS.md と docs/codex-installation.md の
Build from Source に従ってください。既存 checkout の local change は保持し、
target commit、build identity、全 check の結果を検証してください。

同じ source revision に含まれる monika-report、monika、monika-update だけを
active Codex skills directory に配置し、他の Skill は変更しないでください。
最後に toolchain version、commit、CLI path、--version、capabilities、実行した
check、Skill の配置結果を報告してください。
```

### Update

```text
$monika-update を使用して、この環境の Monika を最新の公開済み pre-alpha release へ
更新してください。更新前後の identity、release manifest、CLI path、検証した
SHA-256、CLI と三つの bundled Skill の更新結果、rollback の有無を報告してください。
```

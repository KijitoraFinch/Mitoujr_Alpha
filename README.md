# Monika

Monika は、Agent が異なる形式のファイルに散らばった明示情報を、相互に参照し、
検査し、安全に更新するための CLI 基盤です。

主な利用者は Agent です。人間向けのファイル閲覧 UI を提供するのではなく、Agent が
ワークスペースについて正確に問い合わせ、必要な根拠だけをコンテキストへ取り込み、
変更を検証可能な値として扱うための境界を提供します。人間は、導入、運用方針の設定、
必要に応じた変更の承認を担います。

文書の段落、ソースコードの関数、実験データの一行、ログの一部分は、どれも
「意味を持つ情報の一部分」です。しかし、通常のファイル管理やリンク検査では、
ファイル全体より細かい対象を形式横断で扱えません。Monika は、それぞれの形式を
理解する interpreter を通して、こうした対象を共通の概念として観測します。

たとえば、文書中の主張が実験データの特定行に裏付けられていることや、実装中の
関数が仕様書の特定節に対応していることを、検索結果ではなく明示された関係として
扱います。これにより、次のような問いに再現可能な形で答えられます。

- この文書は、どのデータやコードを根拠にしているか
- このファイルを参照している情報はどこにあるか
- 参照先の削除や変更によって、解決できなくなった参照はないか
- Markdown 内の annotation と sidecar file の記述は一致しているか
- 明示済みの情報から、別の表現へ安全に同期できるか

Monika は Markdown の管理ツールでも、特定の sidecar 形式を正本とするデータベース
でもありません。Markdown、ソースコード、JSONL、ログ、Web から取得した内容、
未知形式の blob は、いずれも同じ種類の入力です。形式ごとの違いを消すのではなく、
違いを interpreter に閉じ込めたうえで、解釈した結果を共通のモデルで扱います。

> [!NOTE]
> リポジトリ名の `Alpha` は、ソフトウェアの成熟度を表す名前ではありません。

## 設計思想

### ファイルではなく、情報の単位を扱う

Monika が列挙する情報の単位を **artifact**、artifact の中から選択できる部分を
**region** と呼びます。

region は単なる行番号ではありません。Markdown では段落や見出し、ソースコードでは
関数や型、JSONL では条件に一致する行、未知形式では byte range というように、
対象の形式に適した selector で表現します。artifact 全体を指すことも、明示的な
selector の一種です。

このモデルにより、「ファイル A がファイル B を参照する」より細かく、
「文書 A の主張が、実験結果 B の `metric = latency` である行に裏付けられる」
という関係を表せます。

### 意味と、その置き場所を分ける

**annotation** は、ある region を主語として、関係の種類を表す predicate と
目的語を持つ明示情報です。
同じ annotation は、Markdown の inline comment、ソースコードの comment、
sidecar entry、生成された index など、複数の場所に表現できます。Monika は
annotation の意味と、それがどこに記述されていたかという表現箇所
（**materialization**）を分けて保持します。

したがって、sidecar file にしかない annotation も直ちに無効とはしません。一方で、
inline と sidecar の一方にしかない状態や、両方の内容が食い違う状態は検出できます。
どれか一つの表現を暗黙の正本にするのではなく、明示情報と由来を保ったまま整合性を
調べるためです。

### reference を、単なる文字列として扱わない

**reference** は、パスや URL の文字列ではなく、artifact の出所（origin）、
region の selector、参照の追跡方法、必要に応じた期待条件を持つ値です。参照先を
解決した結果は、観測時刻と内容識別子（content identity）を持つ **snapshot** として
記録できます。

これにより、「現在も何かに解決できる」だけでなく、「以前に確認した対象から内容が
変わっていないか」「selector が古くなっていないか」を区別して検査できます。
解決できない selector を、似ている別の region へ勝手にずらすことはしません。

また、reference の宣言、文書中などに現れた実際の参照、`supported-by` のような
意味を持つ relation は別の概念です。宣言されているだけの未使用 reference を、
実際に存在する関係として扱うことはありません。

### 明示情報の変換と推測を混ぜない

**derive** は、すでに明示されている情報から別の明示表現を導く操作です。同じ入力
からは同じ編集案を返し、適用後に繰り返しても不要な差分を生成しないことを重視します。
たとえば、Markdown inline annotation から同じ内容の sidecar entry を導けます。

一方、記述されていない関係を推測する操作は **infer** です。推測には確信度や理由が
必要であり、決定的な同期処理とは性質が異なります。Monika は両者を明確に分け、
現在の中核機能は infer を行いません。

### 変更を行う前に、変更そのものを値にする

interpreter、extractor、deriver、その他の extension は、ワークスペースを直接
書き換えません。変更が必要な場合は、理由と由来、適用後の内容識別子を持つ
**ProposedPatch** を返します。既存ファイルの edit patch は変更前の内容識別子と
具体的な text edit を持ち、新規ファイルの create patch は完全な内容を持ちます。

Agent は patch を適用前に検査でき、人間の承認が必要な運用では同じ patch をそのまま
提示できます。書き込みを担当する `apply` は、対象が patch 作成後に変更されて
いないことと、編集結果が宣言された内容識別子になることを検証します。同じ patch を
再度適用した場合は変更なし（no-change）となり、別の内容へ変わっていた場合は
上書きせず競合（conflict）として報告します。

### 設定に手続きを持ち込まない

YAML や JSON の sidecar file に記述するのは、reference、selector、relation、
policy などの宣言的な値だけです。pipeline、条件分岐、command execution のような
手続きは記述しません。設定ファイルを手続き型のワークフロー定義にしないことで、
安全性、互換性、デバッグ可能性、冪等性を保ちます。

形式固有の解釈や検査は、interpreter、annotation extractor、deriver、auditor
といった狭い **capability** として追加します。cache や index は再生成可能な派生物
であり、source artifact と annotation artifact が一次情報です。

## 観測から変更まで

```text
source artifact / annotation artifact
                  │
                  ▼
       interpreter / extractor
                  │
                  ▼
 artifact・region・reference・annotation・relation
       │                 │                   │
       ▼                 ▼                   ▼
   read / related     resolve / check       derive
                                               │
                                               ▼
                                       ProposedPatch
                                               │
                                               ▼
                                       validate / apply
```

Agent が直接読む `read` と `related`、厳密なフィールド参照や編集処理に使う
正規化 JSON は、別々の事実を返すものではありません。同じワークスペースの
観測結果を、Agent の処理段階に応じて異なる形で提示します。

通常の探索では、まず `related` で関係する artifact を絞り込み、必要なものだけを
`read` します。これにより、全 artifact の中間表現を一度にコンテキストへ入れずに
済みます。厳密なフィルタリングには `related --json`、正規化された完全な観測結果が
必要な場合には `inspect` を使用します。

## 試してみる

通常は、公開 Release から OS と architecture に対応する単一 CLI バイナリを
配置する方法を推奨します。CLI の実行に source checkout、OCaml、opam は
必要ありません。三つの Codex Skill は、別の OS 非依存 archive として配布します。
バイナリが提供されない target や独自変更には source build も利用できます。
Codex を利用できる場合は、次のように依頼できます。

```text
Monika の最新の公開済み pre-alpha release を、docs/codex-installation.md に従って
インストールしてください。同じ release の manifest と SHA-256 を検証し、
対象環境用の単一バイナリと三つの Codex Skill の導入結果を報告してください。
```

バイナリ導入、Skill 配置、source build の要件と手順は、
[インストールガイド](docs/codex-installation.md)を参照してください。

配布には、通常利用の `$monika`、更新用の `$monika-update`、問題や提案の報告用の
`$monika-report` という三つの Codex Skill が含まれます。提案、Issue、文句などは、
チャット履歴を含めない content-only bundle として報告できます。`$monika` は固定的な
操作手順を課さず、Agent が目的に応じて CLI を選択するための原則だけを提供します。

インストール後は、付属のサンプルワークスペースをそのまま調べられます。

```sh
# 文書の内容と、そこに宣言された region、reference、annotation を読む
monika read --workspace fixtures/basic --artifact docs/linking.md

# 文書から出ている参照と、文書へ入っている参照をたどる
monika related --workspace fixtures/basic --artifact docs/linking.md

# ワークスペース全体の壊れた参照や表現の不一致を検査する
monika check --workspace fixtures/basic
```

`fixtures/basic` には問題のある例も意図的に含まれています。そのため、最後の
`check` は診断を出力し、終了コード `1` で終了します。

## Agent から使う

### 必要な情報だけを読む

Agent は、関係する artifact を `related` で絞り込み、選択した artifact を `read`
で読みます。

```sh
monika read --workspace <workspace> --artifact <path>
monika related --workspace <workspace> --artifact <path>
monika related --workspace <workspace> --artifact <path> \
  --direction outgoing --predicate supported-by
```

`related` は、実際に観測できた明示的な関係だけを返します。対応していない形式が
含まれる場合も、何もないと断定せず、どこまで解釈できたかを coverage として示します。
既定の出力は Agent が直接読みやすい text です。安定したフィールドを使った処理が
必要な場合は `--json` を指定します。

### 整合性を検査する

```sh
monika check --workspace <workspace>
```

`check` はファイルを書き換えません。現在は、主に次の状態を検出します。

- 解決できない reference
- 解決できなくなった region selector
- 宣言されているが使われていない reference
- inline annotation にだけ存在する記述
- sidecar file にだけ存在する記述
- inline annotation と sidecar file の不一致

### 編集案を検証して適用する

`derive` は、既存の明示情報から編集案を patch として生成します。この時点では
ワークスペースを書き換えません。結果は JSON で返り、編集案は `patches` 配列に
含まれます。

```sh
monika derive \
  --workspace <workspace> \
  --artifact <path> \
  --target sidecar > derive-result.json
```

Agent は `patches` の内容を検査します。結果に patch が一つだけ含まれる場合は、
derive の結果をそのまま dry run と適用に渡せます。

```sh
monika apply --workspace <workspace> --result derive-result.json --dry-run
monika apply --workspace <workspace> --result derive-result.json
```

複数の patch が含まれる結果では `--patch-id` で一つを選びます。patch object を
別ファイルに保存する場合は、従来どおり `--patch` も使用できます。

```sh
monika apply --workspace <workspace> --patch patch.json --dry-run
monika apply --workspace <workspace> --patch patch.json
```

すべての書き込みは `apply` が担当します。patch は適用前の内容と適用後の内容を
識別するため、対象が途中で変更された場合は別の内容を上書きせず、競合として
報告します。

## コマンド

| コマンド | 用途 |
| --- | --- |
| `monika read` | 一つの artifact と、その明示情報を Agent が読む形式で表示する |
| `monika related` | artifact に出入りする明示的な参照や関係を、探索に適した範囲で表示する |
| `monika check` | ワークスペース全体の参照と表現の整合性を検査する |
| `monika derive` | 明示済みの情報から決定的な編集 patch を生成する |
| `monika apply` | patch を検証し、安全に適用する |
| `monika scan` | ワークスペース内の artifact を列挙する |
| `monika inspect` | artifact の解釈結果を正規化された JSON で出力する |
| `monika resolve` | reference を解決し、再現可能な snapshot を出力する |
| `monika capabilities` | 利用できる interpreter、extractor などを表示する |
| `monika extension test` | extension descriptor を検証する |

`scan`、`inspect`、`resolve`、`check`、`derive`、`apply`、
`capabilities` の結果は、機械処理に適した JSON です。CLI の引数、出力、終了コードの
詳細は [CLI 仕様](docs/cli-contract.md)を参照してください。

外部 process との通信も検証する場合は、executable と引数を明示します。

```sh
monika extension test --descriptor extension.json \
  --executable python3 --argument extension.py
```

この検査は stdio JSON-RPC の `monika.describe` と descriptor の一致までを対象にします。
開発中の interpreter extension は、登録せずに `inspect` から一時利用できます。

```sh
monika inspect --workspace . --artifact docs/example.md \
  --extension-descriptor extension.json \
  --extension-executable python3 --extension-argument extension.py
```

この経路では、`monika.describe` の照合後に `monika.observe` を呼びます。
同じ一時 extension が観測した reference は、`resolve` から同じ checked session で
`monika.resolveRegion` を呼んで解決できます。

```sh
monika resolve --workspace . --artifact docs/example.md \
  --reference target --observed-at 2026-08-13T00:00:00Z \
  --extension-descriptor extension.json \
  --extension-executable python3 --extension-argument extension.py
```

外部 extension の作成方法は
[`docs/extension-development.md`](docs/extension-development.md) を参照してください。

`scan` は各 directory の `.gitignore` を自動で適用します。Monika だけから除外したい
path や、`.gitignore` の規則を Monika では取り消したい場合は、同じ構文の
`.monikaignore` を置けます。同じ directory では `.monikaignore` が後から適用されます。
再現性を保つため、Git の global ignore と `.git/info/exclude` は参照しません。

## 現在利用できる範囲

標準機能は、通常ファイルで構成されたローカルワークスペースを対象とし、次の情報を
解釈します。

- CommonMark の HTML comment で宣言された region と annotation
- Markdown の inline link
- `derived` と `authored` の所有領域を分離した宣言的な YAML sidecar file
- JSONL の行に対する等価条件の selector

対応状況は、インストール済みの実行ファイルから確認できます。

```sh
monika capabilities
```

任意のファイルは artifact として列挙できますが、その内容を解釈できるかどうかは
利用可能な capability によって異なります。対応していない形式は無視せず、診断や
coverage に明示します。

## 詳細

- [中核モデルと設計全体](DESIGN.md)
- [annotation と sidecar file の書式](docs/inspect-interpreter.md)
- [Agent が `read` と `related` を使う方法](docs/agent-query-api.md)
- [`check` が報告する診断](docs/check-auditing.md)
- [`derive` と patch の生成規則](docs/derive-sidecar.md)
- [用語集](docs/glossary.md)
- [問題の報告方法](docs/codex-reporting.md)

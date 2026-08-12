# 設計説明

## 中核モデル

このシステムは、以下のモデルを中核にします。

```text
Resource
  Monika が観測を試みる対象。状態が変化する場合や、観測できない場合がある。

Origin
  同じ Resource を再び指そうとする宣言的な値。取得手順ではない。

Observation
  一回の観測で得た有限かつ型付きの固定値。ObservationIdentity によって区別する。

Artifact
  現行の CommandResult で content-backed Observation を表す互換層。

Region
  一つの Observation の全体または部分領域。段落、見出し、関数、型、行、セル、Issue comment など。

Reference
  Region を指すための値。固定参照、追跡参照、浮動参照を区別する。

Annotation
  Region に付与される情報。inline link、source comment、sidecar entry などから得られる。

Relation
  Region と Region、または Region と Reference の意味的関係。

ResolutionSnapshot
  ある時点で Reference や Region を解決した結果。変更検知と再検証に使う。

Diagnostic
  不整合、壊れた参照、古い selector、重複などの診断。

ProposedPatch
  ファイルを変更するための編集案。extension は直接書き込まず、ProposedPatch を返す。

CommandResult
  コマンド実行全体の観測可能な結果。diagnostic、patch、変更された artifact、conflict、summary、exit class などを含む。

WorkspaceSnapshot
  workspace transition の比較に使う、正規化された workspace 状態。ResolutionSnapshot とは別の概念である。
```

Resource、Observation、および Region 解決の言語非依存な責務と、参照実装との対応は
[`docs/resource-observation-model.md`](docs/resource-observation-model.md) に定めます。

外部 extension process との通信には、stdio 上の JSON-RPC 2.0 を使用します。現在は
`monika.describe` による protocol version と capability の照合、`monika.observe`、および
`monika.resolveRegion` の一時 dispatch を実装しています。
通信形式は [`protocol/extension-protocol.md`](protocol/extension-protocol.md)、設計判断の
理由は [`docs/extension-runtime-design.md`](docs/extension-runtime-design.md) に定めます。
Observation の内容は、`ContentIdentity` と対応する `inlineText` または `inlineBase64` として
process 間で転送します。大きな内容向けの `contentUri` は予約済みです。

`Diagnostic` は見つかった問題や注意そのものです。`CommandResult` は、コマンドが何を行い、どう終わったかを表す結果です。`Diagnostic` は `CommandResult` に含まれる要素であり、同じものではありません。

## 正規形と結果同値性

Sugar は意味モデルを所有します。意味モデルは OCaml の代数的データ型と純粋関数で表現します。

外部に出す値は、意味モデルそのものではなく、観測可能な正規形です。正規形は転送用の別概念ではありません。意味モデルから比較可能な値へ写したものです。

```text
Sugar semantic model
  -> normalize
    -> observable normal form
      -> JSON
      -> JSON Schema
      -> golden
```

Bitter は Sugar の内部型や内部手順を移植する必要はありません。Bitter は高速化のために Rust に自然な内部表現を使ってよいです。必要なのは、同じ workspace、同じ command、同じ policy に対して、利用者から見て同じ結果になることです。

一致させる対象は以下です。

```text
final workspace content
created / modified / deleted file set
CommandResult の正規形
Diagnostic の正規形
ProposedPatch の正規形
ResolutionSnapshot の正規形
exit class
```

一致を要求しない対象は以下です。

```text
内部データ構造
内部 traversal order
中間処理の分割単位
非公開 trace
性能最適化のための内部 cache
```

したがって、golden test は stdout JSON だけでは不十分です。`apply` のように workspace を変更する command では、initial workspace snapshot、command、CommandResult、final workspace snapshot を合わせて比較します。

## 抽象スキーマ

以下は概念スキーマです。実装時には、内部モデルそのものではなく、観測可能な正規形を JSON Schema として固定します。Schema の実現方法は PPX や特定の library に限定しません。生成、codec からの導出、独立定義のいずれを選ぶ場合も、正規形との不整合を機械的に検出し、手動同期だけに依存しないことを要件とします。

```ts
type ArtifactDescriptor = {
  id: string;
  origin: ArtifactOrigin;
  mediaType?: string;
  contentIdentity: ContentIdentity;
};

type ArtifactOrigin =
  | { kind: "workspace"; path: string }
  | { kind: "git"; repo: string; rev?: string; path: string }
  | { kind: "web"; url: string }
  | { kind: "generated"; name: string }
  | { kind: "external"; uri: string }
  | { kind: "extension"; provider: string; locator: string };

type ContentIdentity = {
  hash: string;
  size: number;
};

type RegionDescriptor = {
  id: RegionId;
  selector: Selector;
  interpreter?: string;
  interpreterVersion?: string;
  summary?: string;
  range?: TextRange;
  fingerprint?: Fingerprint;
};

type ReferenceRecord = {
  id: ReferenceId;
  target: RegionAddress;
  binding: Binding;
  expect?: Expectation[];
  provenance?: Provenance[];
};

type RegionAddress = {
  artifact: ArtifactOrigin;
  selector: Selector;
  interpreter?: string;
  interpreterVersion?: string;
};

type Selector =
  | { kind: "whole-artifact" }
  | { kind: "region-id"; id: string }
  | { kind: "text-range"; range: TextRange }
  | { kind: "row-filter"; where: Record<string, SelectorLiteral> }
  | { kind: "extension"; schema: string; value: JsonValue };

type Expectation =
  | { kind: "digest"; digest: string };

type RegionId = { artifact: string; local: string };
type ReferenceId = { artifact: string; local: string };
type AnnotationId = { artifact: string; local: string };

type RegionRef =
  | { kind: "resolved"; id: RegionId }
  | { kind: "address"; address: RegionAddress };

// number は JSON integer に限定し、小数は受理しない。
type SelectorLiteral = string | number | boolean;
type JsonValue =
  | null
  | string
  | number
  | boolean
  | JsonValue[]
  | { [key: string]: JsonValue };

type Binding =
  | "pinned"
  | "tracking"
  | "floating";

type AnnotationRecord = {
  id: AnnotationId;
  subject: RegionRef;
  predicate: string;
  object: RegionRef | ReferenceRef | LiteralValue;
  provenance: Provenance[];
  materialization: Materialization[];
};

type Materialization =
  | { kind: "markdown-inline"; artifact: string; range: TextRange }
  | { kind: "source-comment"; artifact: string; range: TextRange }
  | { kind: "sidecar"; artifact: string; path?: string }
  | { kind: "generated-index"; artifact: string };

type ResolutionSnapshot = {
  target: RegionAddress;
  observedAt: string;
  artifactIdentity: ContentIdentity;
  regionFingerprint?: Fingerprint;
  display?: DisplayValue;
};

type Diagnostic = {
  code: string;
  defaultSeverity: "info" | "warning" | "error";
  effectiveSeverity: "info" | "warning" | "error";
  message: string;
  location?: {
    artifact?: string;
    region?: RegionId;
    annotation?: AnnotationId;
    range?: TextRange;
  };
  suggestedFixes: ProposedPatch[];
};

type PatchCommon = {
  id: string;
  target: string; // canonical workspace-relative path
  resultingContentIdentity: ContentIdentity;
  reason: string;
  provenance: Provenance;
};

type ProposedPatch =
  | PatchCommon & {
      operation: "create";
      content: string;
    }
  | PatchCommon & {
      operation: "edit";
      expectedContentIdentity: ContentIdentity;
      edits: TextEdit[];
    };

type CommandStatus =
  | "ok"
  | "diagnostics-found"
  | "patches-proposed"
  | "applied"
  | "conflict"
  | "invalid-input"
  | "internal-error";

type ExitClass =
  | "success"
  | "diagnostic-error"
  | "usage-error"
  | "internal-error";

type CommandResult = {
  schemaVersion: "6";
  command: string;
  status: CommandStatus;
  diagnostics: Diagnostic[];
  patches: ProposedPatch[];
  changedArtifacts: ChangedArtifact[];
  conflicts: Conflict[];
  snapshots: ResolutionSnapshot[];
  artifacts: ArtifactDescriptor[];
  regions: RegionDescriptor[];
  references: ReferenceRecord[];
  annotations: AnnotationRecord[];
  capabilities: CapabilityDescriptor[];
  summary?: Record<string, number | string | boolean>;
  exitClass: ExitClass;
};
```

参照実装では OCaml の意味モデルを一次情報とします。これは extension の実装言語や
ABI を OCaml に固定するものではありません。`Selector.Row_filter` は、検証済みの
field name と型付き literal を key と value に持つ、空でない抽象 map です。
core は selector の構造、不変条件、正規化を所有します。selector を artifact
に対して解決する意味論は interpreter が所有します。各条件を JSONL の行へ
適用する規則は `jsonl` interpreter の責務であり、core は `column` と
`equals` のような interpreter 内部の実行表現へ変換しません。

`RegionAddress.selector` は必須です。artifact 全体を指す場合も selector を
省略せず、`{ kind: "whole-artifact" }` を使います。これは「現在の artifact
全体」を表す意味的 selector であり、`text-range` の `0..size` とは同一視し
ません。`text-range` は特定の byte 範囲を指す selector であり、artifact の
サイズ変更後も自動的に全体を追跡するものではありません。構造的な範囲指定が
必要になった場合、広く共有する selector は `Selector` の variant として標準化します。
個別 extension の selector は、名前付き schema と正規化済み JSON 値を使います。
これにより、ソースコードの構造だけでなく、外部サービス、表形式データ、PDF、実験結果などの
新しい領域指定を core の変更なしに追加できます。

`Expectation` は `Reference` に含まれる閉じた代数的データ型です。Phase 1
では、検証済みの `Content_digest.t` を持つ digest expectation を扱います。
正規形、encoder、JSON Schema、golden は、この意味モデルと意味モデルの
テストが成立した後に派生させます。Reference の command-level 正規形と JSON
Schema は version 3 で固定済みです。最初の JSONL 解決と監査規則は
`docs/check-auditing.md` に記録します。

`resultingContentIdentity` is part of the patch contract rather than hidden
apply state. A repeated application can therefore compare the current content
with the declared result and return no change. It also detects a malformed patch
whose edits do not produce the identity declared by the deriver.

Patch JSON input is a separate boundary from JSON output. `Normal_json` encodes
observable normal forms. The input decoder for `monika apply` reads the
observable `ProposedPatch` shape and constructs semantic values through smart
constructors. It does not deserialize JSON directly into internal records, and
it rejects missing fields, unknown fields, `null`, invalid paths, invalid
content identities, invalid ranges, and empty patch payloads before workspace
state is inspected.

`CommandResult` は command ごとの結果 envelope です。`check` では `diagnostics` が中心になります。`derive` では `patches` が中心になります。`apply` では `changedArtifacts`、`conflicts`、`summary` が重要になります。

上のコードブロックは、現行の観測可能な schema version `"6"` の意味モデルです。
`RegionDescriptor`、`ReferenceRecord`、`AnnotationRecord` は command-level 正規形と
standalone schema の双方で固定されています。`CapabilityDescriptor` も command-level
正規形と standalone schema の双方で固定され、組込み機能の列挙に使用します。
Version 5 では `ProposedPatch` は `create | edit` の閉じた直和です。Version 6 では
extension origin と extension selector を追加し、Whole Region の interpreter を省略できます。
`ContentIdentity` は SHA-256 と byte size
の組であり、
selector の数値 literal は JSON integer だけです。`ProposedPatch.target` は任意の
`ArtifactOrigin` ではなく、canonical workspace path です。

`CommandResult.effect` と payload は排他的です。`No_change` は
`patches`、`changedArtifacts`、`conflicts` を持ちません。
`Patches_proposed` は空でない `patches` だけを持ちます。`Applied` は空でない
`changedArtifacts` だけを持ちます。`Conflicted` は空でない `conflicts` だけを
持ちます。`diagnostics`、`snapshots`、`artifacts`、`summary` は observation または
effect の補助情報として扱い、この排他制約の対象にはしません。各 collection は
空の場合も省略しません。

`conflict` は診断としても表現できますが、`apply` の状態遷移結果でもあります。したがって、構造としては `CommandResult.conflicts` に置き、必要に応じて対応する `Diagnostic` も出します。
filesystem 境界で安全に書けない target は `filesystem-safety` conflict として
表現し、成功した no-change とは区別します。

## workspace 操作の境界

現時点では、workspace 操作も Sugar 内に実装します。共通 workspace runtime は本線ではありません。ただし、後から独立した runtime に切り出せるように、以下は意味判断や filesystem への直接書き込みから分離した module と純粋関数として設計します。

```text
path normalization
content identity
text edit application
conflict detection
workspace snapshot normalization
```

以下のいずれかが継続的に発生した場合は、共通 workspace runtime の POC を検討します。

```text
apply 周辺で Sugar / Bitter 差分が複数回出る
patch schema が filesystem 実行詳細を抱え始める
failure-mode test を両実装に重複して大量に書く必要がある
atomic write や partial failure recovery が早期に重要になる
正規形が実質的に runtime 命令列になり始める
```

POC を行う場合も、最初の境界は `normal proposed patch -> apply text edits -> normalized CommandResult` に限定します。annotation、selector、derive、check、policy の意味判断は runtime に入れません。

実 filesystem に対する `apply` は、純粋な patch application の外側にある境界です。
この境界では、workspace root 外への参照を拒否し、symlink policy を固定し、
Linux、macOS、Windows の native path mapping の差を明示します。containment 判定に
文字列 prefix 判定は使いません。Windows の reparse point、reserved name、
case-insensitive filesystem、Unicode normalization のような platform 差は、実装前に
安全側の policy と test を固定します。既存 regular file への text edit だけを扱います。
同一内容であれば no-change として書き込みません。書き込みが必要な場合は、同一
directory 内の temporary file に完全な replacement content を書き、検証後に atomic
rename で置き換えます。途中で失敗した場合は元 file を保持し、成功したと観測できない
状態を `applied` として報告しません。
詳細な境界条件は [apply filesystem boundary](docs/apply-filesystem-boundary.md) に置きます。
read-only scan の境界条件と未解決の concurrency 制約は
[scan filesystem boundary](docs/scan-filesystem-boundary.md) に置きます。

## CLI の中核

最初に固定する CLI は以下です。

```text
monika scan
  ワークスペースから Artifact を列挙する。

monika inspect
  Artifact を解釈し、Region、Annotation、Reference 候補を出す。

monika resolve
  Reference または Region を現在のワークスペース上で解決する。

monika check
  不整合、壊れた参照、重複、古い selector などを診断する。

monika derive
  既に明示された情報から、sidecar や inline 表現への編集案を導出する。

monika apply
  derive や check が返した ProposedPatch を安全に適用する。

monika capabilities
  現在利用可能な capability を列挙する。

monika extension test
  extension が契約を満たしているか検査する。
```

## derive と infer の区別

`derive` と `infer` は分けます。

`derive` は、既に明示された情報から別表現を導く操作です。原則として決定的であり、冪等です。
最初の inline-to-sidecar 実装と編集可能な YAML surface は
`docs/derive-sidecar.md` に固定します。

例:

```text
Markdown inline link から sidecar entry を導く
sidecar entry から Markdown comment を導く
source comment から annotation record を導く
annotation record から index entry を導く
```

`infer` は、明示されていない関係や注釈を推測する操作です。出力は候補であり、confidence、reason、provenance を持ちます。初期中核には入れなくてよいです。

この区別により、core の信頼性を保ちます。

## extension protocol

extension は、狭い capability を提供します。設定ファイルに手続きを書かせません。

```ts
type CapabilityDescriptor = {
  type:
    | "artifact-provider"
    | "interpreter"
    | "annotation-extractor"
    | "deriver"
    | "auditor"
    | "renderer"
    | "indexer";
  name: string;
  version: string;
  appliesTo?: {
    mediaTypes: string[];
    pathGlobs: string[];
  };
  schemas?: {
    selector?: string;
    annotation?: string;
    options?: string;
  };
};

type ExtensionDescriptor = {
  protocolVersion: "1";
  capability: CapabilityDescriptor;
};

type ContentTransfer =
  | { kind: "inlineText"; text: string }
  | { kind: "inlineBase64"; base64: string }
  | {
      kind: "contentUri";
      uri: string;
      contentIdentity: ContentIdentity;
      expiresWith?: "session";
    };

// 以下は特定言語の interface ではなく、値の入出力関係を示す。
observe:
  Artifact
  × ContentTransfer
  -> Observation | Failure

resolveRegion:
  InterpreterIdentity
  × Artifact
  × ContentTransfer
  × Selector
  -> Region | Failure

extractAnnotations:
  Observation
  -> AnnotationCandidate[] | Failure

derive:
  DeriveInput
  -> { patches: ProposedPatch[]; diagnostics: Diagnostic[] } | Failure
```

`monika extension test --descriptor <file>` は、上記の `ExtensionDescriptor` を厳密に
検査します。`--executable` と反復可能な `--argument` を追加した場合は、shell を介さず
外部 process を起動し、stdio 上の JSON-RPC 2.0 で `monika.describe` を呼びます。process
が返した protocol version と capability は、静的 descriptor と一致しなければなりません。
message size、timeout、EOF 後の終了条件、および受信 JSON の検査規則は
[`protocol/extension-protocol.md`](protocol/extension-protocol.md) に定めます。

`monika inspect` は、CLI で明示された一時的な interpreter extension に
`monika.observe` を dispatch できます。`monika resolve` は、同じ checked session で source
の `monika.observe` と target の `monika.resolveRegion` を順に呼べます。Observation の内容転送は、text document では
なく `ContentIdentity` を持つ read-only byte resource として扱います。小さい内容は
`inlineText` または `inlineBase64`、大きい内容は将来の `contentUri` で渡します。この判断の
詳細は [`docs/extension-runtime-design.md`](docs/extension-runtime-design.md) に記載します。
process 間の値は言語非依存の schema で定義し、OCaml の内部値を直列化したものを契約には
しません。

## extension の制約

extension は以下の制約を守ります。

```text
store を直接変更しない
ファイルを直接書き換えない
書き換えが必要な場合は ProposedPatch を返す
同じ入力に対して不要な差分を出さない
解決不能な selector を勝手に近い region へずらさない
診断には安定した code を付ける
出力は schema version を持つ
```

## 標準 capability

初期実装に含める標準 capability は以下です。

```text
ArtifactProvider
  workspace file
  git identity

Interpreter
  blob
  markdown
  sidecar
  json
  jsonl
  TypeScript または Python のどちらか一つ

AnnotationExtractor
  markdown inline link
  markdown HTML comment
  source comment tag
  sidecar entry

Deriver
  inline annotation -> sidecar patch
  sidecar annotation -> markdown comment patch
  source comment -> sidecar patch

Auditor
  sidecar-only
  inline-only
  divergent
  stale-selector
  duplicate
  unreferenced-ref
  unresolved-ref
  expectation-failed
```

## 保存形式

最初は、永続 store を複雑にしません。

```text
source artifacts
  Markdown、source code、JSONL、その他のファイル

annotation artifacts
  *.annotations.yaml または .monika/*.yaml

snapshot cache
  .monika/snapshots/*.json

index cache
  .monika/index/*.json
```

cache は再生成可能です。信頼する一次情報は、source artifact と annotation artifact です。

## sidecar の最小例

```yaml
version: 1

derived:
  refs: {}
  annotations: {}

authored:
  refs:
    latency-run-a:
      target:
        artifact:
          origin:
            kind: workspace
            path: runs/a/metrics.jsonl
        selector:
          kind: row-filter
          where:
            metric: latency
        interpreter: jsonl
      binding:
        mode: pinned
      expect:
        - digest: sha256:...

  annotations:
    latency-evidence:
      subject:
        artifact:
          origin:
            kind: workspace
            path: docs/linking.md
        selector:
          kind: region-id
          id: claim-sidecar-friction
        interpreter: markdown
      predicate: supported-by
      object:
        ref: latency-run-a
```

この YAML には手続きがありません。参照、selector、binding、expectation、relation だけがあります。
`derived` は Monika が管理し、`authored` はユーザーが管理します。同じ ID が両方に
ある場合は `authored` のレコード全体を優先し、field-level の deep merge は行いません。
最初の実装が受理する厳密な構文、Markdown 表現との統合規則、filesystem read 境界は
`docs/inspect-interpreter.md` に固定します。

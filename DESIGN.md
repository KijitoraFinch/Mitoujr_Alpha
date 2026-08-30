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

Interpretation
  一つの固定済み Observation を Interpreter で解釈した結果。Observation を生成、変更、または再分類しない。

Region
  一つの Observation の全体または部分領域。段落、見出し、関数、型、行、セル、Issue comment など。

Reference
  Region を指すための値。固定参照、追跡参照、浮動参照を区別する。

Annotation
  Region についての明示的な主張を表す意味値。保存形式と宣言位置は Annotation 自身に含めない。

Relation
  Region と Region、または Region と Reference の意味的関係。

ResolutionSnapshot
  ある時点で Reference や Region を解決した結果。変更検知と再検証に使う。

Diagnostic
  不整合、壊れた参照、古い selector、重複などの診断。

ProposedPatch
  ファイルを変更するための編集案。extension は直接書き込まず、ProposedPatch を返す。

CommandResult
  コマンド実行全体の観測可能な結果。diagnostic、patch、変更された observation、conflict、summary、exit class などを含む。

WorkspaceSnapshot
  workspace transition の比較に使う、正規化された workspace 状態。ResolutionSnapshot とは別の概念である。
```

Resource、Observation、および Region 解決の言語非依存な責務と、参照実装との対応は
[`docs/resource-observation-model.md`](docs/resource-observation-model.md) に定めます。
Annotation、Reference、それらが記述された位置、および Sidecar document の責務分離は
[`docs/annotation-reference-storage-model.md`](docs/annotation-reference-storage-model.md) に定めます。
実装コンセプト、意味型、schema version 11、および参照実装は、この責務分離に従います。

外部 extension process との通信には、stdio 上の JSON-RPC 2.0 を使用します。現在は
`monika.initializeSession` による protocol version と capability の照合、
capability ごとの method と dispatcher を実装しています。
通信形式は [`protocol/extension-protocol.md`](protocol/extension-protocol.md)、設計判断の
理由は [`docs/extension-runtime-design.md`](docs/extension-runtime-design.md) に定めます。
byte-backed Observation の内容は、`ContentIdentity` と対応する bounded host-owned
stream として process 間で転送します。構造化 Observation は schema identity と
正規化済み value として渡します。Resource Observer が生成した byte 列も、逆方向の
bounded stream を通して host が固定してから受理します。

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
type Observation = {
  id: string;
  origin: Origin;
  identity: ObservationIdentity;
  contentIdentity?: ContentIdentity;
};

type ObservationType = {
  name: string;
  version: string;
};

type ObservationIdentity = {
  observationType: ObservationType;
  key: string;
};

type Origin =
  | { kind: "workspace"; path: string }
  | { kind: "git"; repo: string; rev?: string; path: string }
  | { kind: "web"; url: string }
  | { kind: "generated"; name: string }
  | { kind: "external"; uri: string }
  | { kind: "extension"; observer: string; locator: string };

type ContentIdentity = {
  hash: string;
  size: number;
};

// Observation ではない。上位 metadata file を一操作中に固定した読み取り値。
type SidecarSnapshot = {
  path: string;
  contentIdentity: ContentIdentity;
};

type Region = {
  id: RegionId;
  selector: Selector;
  interpreter?: string;
  interpreterVersion?: string;
  summary?: string;
  range?: TextRange;
  fingerprint?: Fingerprint;
};

type Reference = {
  id: ReferenceId;
  target: RegionAddress;
  binding: Binding;
  expect?: Expectation[];
};

type RegionAddress = {
  origin: Origin;
  selector: Selector;
  interpreter?: string;
  interpreterVersion?: string;
  expectation?: Expectation;
};

type Selector =
  | { kind: "whole-observation" }
  | { kind: "region-id"; id: string }
  | { kind: "text-range"; range: TextRange }
  | { kind: "row-filter"; where: Record<string, SelectorLiteral> }
  | { kind: "extension"; schema: string; value: JsonValue };

type Expectation =
  | { kind: "observation-identity"; observationIdentity: ObservationIdentity }
  | { kind: "content-identity"; contentIdentity: ContentIdentity }
  | { kind: "revision"; schema: string; value: JsonValue }
  | { kind: "fingerprint"; schema: string; value: JsonValue };

type RegionId = { observation: string; local: string };
type ReferenceId = { scope: Origin; local: string };
type AnnotationId = { scope: Origin; local: string };

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

type Annotation = {
  id: AnnotationId;
  subject: RegionRef;
  predicate: string;
  object: RegionRef | ReferenceRef | LiteralValue;
};

type SourceLocation =
  | {
      kind: "observation";
      observation: string;
      locator: SourceLocator;
      encoding: "markdown-inline" | "source-comment";
    }
  | {
      kind: "sidecar";
      path: string;
      contentIdentity: ContentIdentity;
      locator: StructuredLocation;
      ownership: "authored" | "derived";
    };

type SourceLocator =
  | { kind: "byte-range"; range: TextRange }
  | { kind: "structured"; location: StructuredLocation };

type StructuredLocation = {
  path: (string | number)[];
};

type AnnotationOccurrence = {
  annotation: Annotation;
  source: SourceLocation;
};

type ReferenceDefinitionOccurrence = {
  reference: Reference;
  source: SourceLocation;
};

type ResolutionSnapshot = {
  target: RegionAddress;
  observedAt: string;
  observationIdentity: ObservationIdentity;
  regionFingerprint?: Fingerprint;
  display?: DisplayValue;
};

type ProtocolValue =
  | null
  | boolean
  | string
  | number // safe integer only
  | ProtocolValue[]
  | { [name: string]: ProtocolValue };

type ExtensionFailure = {
  operation:
    | "session"
    | "interpret-observation"
    | "resolve-region"
    | "classify-region-extents";
  code: string;
  data?: ProtocolValue;
};

type Diagnostic = {
  code: string;
  defaultSeverity: "info" | "warning" | "error";
  effectiveSeverity: "info" | "warning" | "error";
  message: string;
  location?: {
    observation?: string;
    region?: RegionId;
    annotation?: AnnotationId;
    range?: TextRange;
  };
  extensionFailure?: ExtensionFailure;
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
  schemaVersion: string; // exact literal is fixed by the wire specification
  command: string;
  status: CommandStatus;
  diagnostics: Diagnostic[];
  patches: ProposedPatch[];
  changedFiles: ChangedFile[];
  conflicts: Conflict[];
  snapshots: ResolutionSnapshot[];
  observations: Observation[];
  regions: Region[];
  references: Reference[];
  annotations: Annotation[];
  capabilities: Capability[];
  summary?: Record<string, number | string | boolean>;
  exitClass: ExitClass;
};
```

参照実装では OCaml の意味モデルを一次情報とします。これは extension の実装言語や
ABI を OCaml に固定するものではありません。`Selector.Row_filter` は、検証済みの
field name と型付き literal を key と value に持つ、空でない抽象 map です。
core は selector の構造、不変条件、正規化を所有します。selector を observation
に対して解決する意味論は interpreter が所有します。各条件を JSONL の行へ
適用する規則は `jsonl` interpreter の責務であり、core は `column` と
`equals` のような interpreter 内部の実行表現へ変換しません。

`RegionAddress.selector` は必須です。observation 全体を指す場合も selector を
省略せず、`{ kind: "whole-observation" }` を使います。これは「現在の observation
全体」を表す意味的 selector であり、`text-range` の `0..size` とは同一視し
ません。`text-range` は特定の byte 範囲を指す selector であり、observation の
サイズ変更後も自動的に全体を追跡するものではありません。構造的な範囲指定が
必要になった場合、広く共有する selector は `Selector` の variant として標準化します。
個別 extension の selector は、名前付き schema と正規化済み JSON 値を使います。
これにより、ソースコードの構造だけでなく、外部サービス、表形式データ、PDF、実験結果などの
新しい領域指定を core の変更なしに追加できます。

`Region` と `RegionAddress` は、Whole Observation の場合に `interpreter` と
`interpreterVersion` を両方とも省略し、部分領域の場合に exact name/version を両方とも
必須とします。Extension result の欠落 field を manifest から暗黙に補完しません。

`Expectation` は閉じた代数的データ型です。ObservationIdentity、ContentIdentity、
Origin が証拠として保持する schema 付き revision、または Interpreter が生成する schema 付き
fingerprint のいずれかを要求します。schema 付き値は schema identity と正規化済み JSON value の
組であり、revision と fingerprint を同じ文字列として比較しません。

`RegionAddress.expectation` は、その address を解決するたびに検証する不変条件です。
`Reference.expectations` は `Pinned` binding が固定する期待値です。`Pinned` は address または
Reference に少なくとも一つの expectation を必要とします。`Tracking` と `Floating` は
Reference 側に pinned expectation を持ちません。`Tracking` は任意の前回
`ResolutionSnapshot` と今回の ObservationIdentity および Region fingerprint を比較し、差があれば
`resolution-changed` を報告します。`Floating` は前回 Snapshot との一致を要求しません。
正規形、encoder、JSON Schema、golden は、この意味モデルと意味モデルの
テストが成立した後に派生させます。Reference の command-level 正規形と JSON
Schema は現行 schema version 11 と同時に固定します。最初の JSONL 解決と監査規則は
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

`CommandResult` は command ごとの結果 envelope です。`check` では `diagnostics` が中心になります。`derive` では `patches` が中心になります。`apply` では `changedFiles`、`conflicts`、`summary` が重要になります。

上のコードブロックは概念上の区別を示すものであり、現行 wire schema version `"11"` の
正確な shape は `schemas/` と golden fixture が定めます。Version 10 は保存位置を
Annotation の意味値から分離し、Sidecar を Observation ではなく SidecarSnapshot として扱い、
Reference definition、ReferenceUse、および Annotation occurrence を専用の型で公開します。
旧 shape の別名、legacy decoder、または暗黙の変換は持ちません。

Version 5 では `ProposedPatch` は `create | edit` の閉じた直和です。Version 6 では
extension origin と extension selector を追加し、Whole Region の interpreter を省略できます。
Version 7 では一般の `Observation` を正規形へ直接公開し、`ContentIdentity` は byte 列を
持つ Observation の任意の補助情報になりました。
Version 8 では Extension の失敗について、operation、Extension 固有の code、および
任意の protocol data を構造化された診断詳細として保持します。
Version 9 では Observation の host-owned representation を明示し、extension origin に
Resource Observer の name/version identity と normalized locator を保持します。
Version 10 では Origin-scoped semantic ID、typed occurrence、Coverage、SidecarSnapshot、
および WorkspaceGraphSnapshot を追加します。
Version 11 では schema 付き fingerprint、四種類の Observation expectation、
RegionAddress expectation、および Tracking の `resolution-changed` 診断を追加します。
`ContentIdentity` は SHA-256 と byte size
の組であり、
selector の数値 literal は JSON integer だけです。`ProposedPatch.target` は任意の
`Origin` ではなく、canonical workspace path です。

`CommandResult.effect` と payload は排他的です。`No_change` は
`patches`、`changedFiles`、`conflicts` を持ちません。
`Patches_proposed` は空でない `patches` だけを持ちます。`Applied` は空でない
`changedFiles` だけを持ちます。`Conflicted` は空でない `conflicts` だけを
持ちます。`diagnostics`、`snapshots`、`observations`、typed occurrences、`coverage`、
`summary` は observation または
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
case-insensitive filesystem、Unicode normalization のような platform 差については、
安全側の policy と test を実装境界に固定します。安全な parent directory の下への
regular file の新規作成と、既存 regular file への text edit を扱います。同一内容で
あれば no-change として書き込みません。書き込みが必要な場合は、同一 directory 内の
temporary file に完全な replacement content を書き、検証後に atomic な作成または
置換を行います。途中で失敗した場合は元 file を保持し、成功したと観測できない状態を
`applied` として報告しません。
詳細な境界条件は [apply filesystem boundary](docs/apply-filesystem-boundary.md) に置きます。
read-only scan の境界条件と未解決の concurrency 制約は
[scan filesystem boundary](docs/scan-filesystem-boundary.md) に置きます。

## CLI の中核

最初に固定する CLI は以下です。

```text
monika scan
  ワークスペースから Observation を列挙する。

monika inspect
  Observation を解釈し、Region、Annotation、Reference 候補を出す。

monika resolve
  Reference または RegionAddress を現在の Observation と Region へ解決する。

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
type Capability = {
  type:
    | "resource-observer"
    | "interpreter"
    | "annotation-extractor"
    | "reference-extractor"
    | "deriver"
    | "auditor";
  name: string;
  version: string;
  acceptedObservationTypes: ObservationType[];
  applicability: {
    pathGlobs: string[];
  };
  selectorSchemas: string[];
  resultSchemas: NonEmpty<string>;
};

type ExtensionManifest = {
  protocolVersion: "1";
  capability: Capability;
};

// pathGlobs は workspace-relative path 全体へ case-sensitive に適用する。
// segment 内の * と、segment 全体を占める ** だけを wildcard とする。
// acceptedObservationTypes は name と version の完全一致で評価する。
// workspace Origin では pathGlobs も満たす必要がある。
// 候補選択を行う操作で複数 Interpreter が適用される場合は失敗する。

type ContentTransfer = {
  kind: "byteStream";
  byteLength: number;
};

// request の直後に host が bounded contentChunk と endContent を送る。
// host content の絶対 path、再取得用 URI、host resource token は Extension へ渡さない。
// Observation と RegionAddress の宣言的な Origin は、この所在情報と区別する。

type Interpretation = {
  interpreter: InterpreterIdentity;
  observation: ObservationId;
  regions: Region[];
};

type ReferenceExtraction = {
  definitions: ReferenceDefinitionOccurrence[];
  uses: ReferenceUse[];
};

type AnnotationExtraction = {
  occurrences: AnnotationOccurrence[];
};

// protocol version 1 が実装する、言語非依存の値の入出力関係。
interpretObservation:
  InterpreterIdentity
  × Observation
  × ContentTransfer?
  -> Interpretation | Failure

resolveRegion:
  InterpreterIdentity
  × Observation
  × ContentTransfer?
  × Selector
  -> Region | Failure

extractReferences:
  ReferenceExtractorIdentity
  × Observation
  × Interpretation?
  × ContentTransfer?
  -> ReferenceExtraction | Failure

extractAnnotations:
  AnnotationExtractorIdentity
  × Observation
  × Interpretation?
  × ContentTransfer?
  -> AnnotationExtraction | Failure

observeResource:
  ResourceObserverIdentity × Origin
  -> Observation | Failure

audit:
  AuditorIdentity × WorkspaceGraphSnapshot × AuditPolicy
  -> Diagnostic[] | Failure

derive:
  DeriverIdentity × WorkspaceGraphSnapshot × DeriveRequest
  -> ProposedPatch[] | Failure

```

`DeriveRequest` は一つの `AnnotationOccurrence` または
`ReferenceDefinitionOccurrence`、target Origin、target encoding、および宣言的 policy を
保持します。source Origin 全体や列挙順を source occurrence の代用にはしません。

protocol version 1 は、Resource Observer、Interpreter、Annotation Extractor、
Reference Extractor、Auditor、Deriver、および Region の解決・比較に、それぞれ独立した
runtime method を持ちます。manifest の `selectorSchemas` と `resultSchemas` は method の
意味契約を宣言し、checked session の初期化応答と完全一致させます。

`monika extension test --manifest <file>` は、上記の `ExtensionManifest` を厳密に
検査します。`--executable` と反復可能な `--argument` を追加した場合は、shell を介さず
外部 process を fail-closed sandbox で起動し、stdio 上の JSON-RPC 2.0 で
`monika.initializeSession` と capability が宣言するすべての method を呼びます。process
が返した protocol version と capability は、静的 manifest と一致しなければなりません。
各 method は型付きの合成入力に対する成功値または Failure を返さなければなりません。
message size、timeout、EOF 後の終了条件、および受信 JSON の検査規則は
[`protocol/extension-protocol.md`](protocol/extension-protocol.md) に定めます。

Installed Extension は manifest、絶対 executable path、引数配列、および authority を
workspace 外の RegistrySnapshot に保持します。通常 role の authority は明示した launch path
だけを read-only で公開し、network を拒否します。Resource Observer だけは Extension Origin
の観測に必要な read-only path と network access を別の authority variant で受け取れます。
親 process の環境変数、workspace 権限、および current working directory は継承しません。

`monika inspect` は一意に選択した Interpreter を実行し、適用可能な Annotation Extractor と
Reference Extractor の結果を加算します。`monika resolve` は Reference の source と target を
独立に固定する経路に加え、正規化済み RegionAddress を直接受け取る経路を持ちます。どちらも
exact Interpreter identity と exact Resource Observer identity を使い、成功時には target
Observation、Region、および ResolutionSnapshot を返します。`check` はすべての有効な Auditor を、`derive` は
明示した Deriver を、同じ固定済み `WorkspaceGraphSnapshot` に対して実行します。Observation の
byte 内容は host-owned stream として扱います。この判断の
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
ResourceObserver
  workspace file

Interpreter
  markdown
  jsonl

AnnotationExtractor
  markdown inline link
  markdown HTML comment

ReferenceExtractor
  markdown inline reference

Deriver
  inline annotation -> sidecar patch

Auditor
  sidecar-only
  inline-only
  divergent
  stale-selector
  duplicate
  unreferenced-ref
  unresolved-ref
  expectation-failed
  resolution-changed
```

Sidecar は Observation capability の入力ではありません。Core の metadata loader と decoder が
SidecarSnapshot を固定して、AnnotationOccurrence と ReferenceDefinitionOccurrence を構築します。
将来、外部 decoder を許す場合も、Observation Extractor とは独立した protocol とします。

## 保存形式

最初は、永続 store を複雑にしません。

```text
primary observations
  Markdown、source code、JSONL、その他のファイル

sidecar metadata
  primary Observation に関する宣言値を格納する file
  metadata loader が SidecarSnapshot として固定する
  Resource inventory、Interpreter dispatch、Observation coverage には入れない

snapshot cache
  .monika/snapshots/*.json

index cache
  .monika/index/*.json
```

cache は再生成可能です。信頼する一次情報は primary Observation と SidecarSnapshot ですが、
両者は同じ意味階層ではありません。Sidecar は primary Observation を補強する上位 metadata です。

## sidecar の最小例

```yaml
version: 2

scope:
  origin:
    kind: workspace
    path: docs/linking.md

authored:
  refs:
    latency-run-a:
      target:
        origin:
          kind: workspace
          path: runs/a/metrics.jsonl
        selector:
          kind: row-filter
          where:
            metric: latency
        interpreter: jsonl
        interpreterVersion: "1"
      binding:
        mode: pinned
      expect:
        - contentIdentity:
            hash: sha256:...
            size: 123

  annotations:
    latency-evidence:
      subject:
        origin:
          kind: workspace
          path: docs/linking.md
        selector:
          kind: region-id
          id: claim-sidecar-friction
        interpreter: markdown
        interpreterVersion: "1"
      predicate: supported-by
      object:
        ref: latency-run-a

derived:
  refs: {}
  annotations: {}
```

この YAML には手続きがありません。参照、selector、binding、expectation、relation だけがあります。
`derived` は Monika が管理し、`authored` はユーザーが管理します。ownership は編集権限を
定める値であり、意味上の優先順位ではありません。同じ scoped ID に異なる値があれば、
どちらも保持して Conflict として検出します。
最初の実装が受理する厳密な構文、Markdown 表現との統合規則、filesystem read 境界は
`docs/inspect-interpreter.md` に固定します。

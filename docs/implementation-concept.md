# Monika の実装コンセプトと中核モデル

## この文書の役割

この文書は、Monika を実装する際の判断基準となる中核モデルを定めます。各実装は、内部の
module 構成や使用言語を自由に選べますが、ここで定める値の意味、操作の境界、失敗の扱い、
および観測可能な結果を維持します。

Monika は、自然言語文書、source code、実験 data、log、Web 由来の内容、および未知形式の
blob を、形式ごとの意味を保ったまま横断的に扱うための基盤です。Agent は Monika を通じて、
workspace 内外の情報を列挙し、必要な部分を選び、明示された関係をたどり、不整合を検査し、
安全な編集案を作成します。

## 目的

Monika が提供する中心的な能力は次のとおりです。

- 観測対象を宣言的な値で指し、一回の処理で固定された結果を得る。
- 固定された結果の全体または部分領域を、形式に適した規則で解釈する。
- Annotation、Reference、および実際の Reference 使用箇所を抽出する。
- 明示情報から workspace 全体の関係 graph を構築する。
- 参照先、selector、期待条件、および複数の記載箇所の整合性を検査する。
- 既存の明示情報から別の保存表現を決定的に導出する。
- 変更を検証可能な Patch として提示し、競合を検査して適用する。
- 新しい Resource Observer、Interpreter、Extractor、Auditor、および Deriver を追加する。

この目的のため、Monika は状態と処理を明示的な値として扱います。同じ正規化済み入力には
同じ結果が対応し、すべての処理境界は成功値または構造化された Failure を返します。

## 設計原則

- workspace の設定と Sidecar は、Origin、Selector、Annotation、Reference、policy、schema version
  などの宣言値を持ちます。実行手続きは、Core と install 済み capability が所有します。
- Resource の現在状態、固定済み Observation、および Observation に関する metadata を別々の値として
  扱います。
- Markdown、source code、structured data、および未知形式の blob は、同じ Resource/Observation
  model に従います。形式固有の規則は capability が所有します。
- 読み取り、解釈、抽出、検査、導出、および適用を独立した操作にします。
- workspace の変更案を ProposedPatch として値にし、Core の apply が書き込みを担当します。
- 候補選択、失敗、競合、および coverage を結果に明示します。
- cache と index は、一次入力の identity と capability version から再構築できる派生物にします。

## 基本表記

- `Identity` は、値や規則の同一性を比較するための安定した値です。capability identity は原則として
  name と version の組です。
- `Id` は、一つの結果や snapshot 内で値を参照する識別子です。`ObservationId` と
  `ObservationIdentity` は異なる役割を持ちます。
- `NormalizedValue` は、同値判定と正規順序が定義された schema-validated value です。
- `WorkspacePath` は、workspace root を基準に正規化され、containment を検証済みの相対 path です。
- `ByteRange` は、固定された byte 列に対するゼロ起点の半開区間 `[start, end)` です。
- `NonEmpty<T>` は、少なくとも一件を持つ collection です。

## 全体構造

Monika の処理は、次の層から構成されます。

```text
Resource plane
  Origin -> Resource Observer -> Observation

Interpretation plane
  Observation + Interpreter -> Interpretation / Region

Metadata plane
  Sidecar file -> SidecarSnapshot -> SidecarContents

Explicit-information plane
  Observation Extractors ---------------------+
                                                +-> typed indexes
  SidecarContents -----------------------------+

Workspace plane
  Observations + Regions + typed indexes
    -> Reference resolution
    -> Relation graph
    -> Diagnostics and coverage

Change plane
  Explicit occurrences -> Deriver -> ProposedPatch -> Core apply
```

Resource の状態、固定済み Observation、Observation 内の Region、および Observation に関する
metadata は、それぞれ異なる層の値です。Core は各層の値を保ったまま組み合わせます。

## Resource、Origin、および Observation

### Resource

`Resource` は、Monika が状態の観測を試みる対象です。workspace の file entry、Git object、
Web page、GitHub Issue、実験 log stream などが Resource になります。

Resource は時間とともに変化でき、ある時点では取得に失敗できます。一つの Resource を異なる
時点で観測すると、異なる Observation を得られます。

### Origin

`Origin` は、Resource を再び指そうとする正規化可能な宣言値です。

```text
Origin =
  | WorkspacePath
  | GitLocation
  | WebUrl
  | GeneratedName
  | ExternalUri
  | ExtensionOrigin {
      observer: ResourceObserverIdentity,
      locator: NormalizedValue
    }
```

同じ正規化済み Origin は、同じ Resource を指そうとする値として比較します。Origin は取得手順を
記述せず、対応する Resource Observer を選ぶための情報を持ちます。

### Resource Observer

`Resource Observer` は、Origin が指す Resource の状態を一回観測して固定する capability です。

```text
ResourceObserverIdentity = name × version
```

```text
observeResource(
  ResourceObserverIdentity,
  Origin
) -> Observation | ObservationFailure
```

workspace file の Observer は Core に組み込みます。外部 service や独自 Resource の Observer は、
Extension として追加できます。Observer は ObservationType と ObservationIdentity の生成規則を
所有し、同じ identity が同じ型と同じ観測可能な値を表すことを保証します。

### Observation

`Observation` は、一回の観測で得た有限かつ型付きの固定値です。

```text
Observation
  id: ObservationId
  origin: Origin
  identity: ObservationIdentity
  representation: HostOwnedObservationValue
  contentIdentity?: ContentIdentity
```

```text
ObservationIdentity
  observationType: ObservationType
  key: StableIdentityKey

ObservationType
  name: string
  version: string
```

一回の処理中、Observation の型、identity、および観測可能な内容は固定値として扱います。
Resource を再観測して状態が変わっていた場合は、新しい Observation を作ります。

`HostOwnedObservationValue` は、Observer が返した有限の値を Core が固定して保持する境界です。
ObservationType は、その値の意味と capability への転送表現を定めます。構造化された外部 Resource
も、型に対応した正規表現を host 側へ固定してから後続 capability へ渡します。

byte 列で表現できる Observation は、`ContentIdentity` と host-owned content stream を持てます。

```text
ContentIdentity
  digest: Digest
  size: NonNegativeInteger
```

ContentIdentity は byte 列の同一性、range の検証、cache の無効化、および Patch の競合検査に
使用します。ObservationIdentity は ObservationType を含み、Observer が定めた観測結果全体の
同一性を表します。

すべての Observation は、その全体を表す Whole Region を一つ持ちます。

## Interpreter、Selector、および Region

### Interpreter

`Interpreter` は、一つの固定済み Observation に含まれる明示的な Region 構造と、Region を
解決・比較する規則を所有する capability です。名前と version の組が解釈規則の identity です。

```text
InterpreterIdentity = name × version
```

Interpreter は次の操作を実装します。

```text
interpretObservation(
  InterpreterIdentity,
  Observation
) -> Interpretation | InterpretationFailure

resolveRegion(
  InterpreterIdentity,
  Observation,
  Selector
) -> Region | RegionResolutionFailure

classifyRegionExtents(
  InterpreterIdentity,
  Observation,
  Region,
  Region
) -> RegionExtentRelation | RegionComparisonFailure
```

`Interpretation` は、入力 Observation の Region 構造だけを有限の値として表します。Annotation と
Reference は、専用 Extractor の結果として保持します。

```text
Interpretation
  interpreter: InterpreterIdentity
  observation: ObservationId
  regions: Region[]
```

Region の有限列挙と Selector による一件の解決は、独立した操作です。Interpreter は、列挙に適さない
大きな空間の Region も Selector から直接解決できます。

### Selector と RegionAddress

`Selector` は、Observation の全体または部分領域を宣言的に指定する値です。built-in Selector は
Whole Observation、local Region ID、byte range、row filter などを表します。Extension Selector は、
schema identity と正規化済み JSON value の組です。

部分 Region の意味は、次の入力全体によって決まります。

```text
InterpreterIdentity × ObservationIdentity × Selector
```

`RegionAddress` は、将来の観測と解決に使う宣言値です。

```text
RegionAddress
  origin: Origin
  selector: Selector
  interpreter?: InterpreterIdentity
  expectation?: ObservationExpectation
```

`ObservationExpectation` は、解決時に要求する ObservationIdentity、ContentIdentity、revision、または
型固有の fingerprint を schema 化した値です。binding は、いつ expectation を固定し、再観測時に
どの差を報告するかを定めます。

Whole Observation は Interpreter を指定せずに解決できます。部分 Region は、その Selector を所有する
Interpreter identity を明示します。

### Region

`Region` は、一つの固定済み Observation の全体または部分領域です。

```text
Region
  id: RegionId
  observation: ObservationId
  extent:
    | WholeObservation
    | ResolvedExtent {
        interpreter: InterpreterIdentity,
        selector: Selector
      }
  summary?: DisplayValue
  byteRange?: ByteRange
  fingerprint?: Fingerprint
```

```text
RegionId = ObservationId × LocalRegionId

RegionRef =
  | Resolved(RegionId)
  | Address(RegionAddress)
```

解決結果の Region は、解決に使用した ObservationIdentity、InterpreterIdentity、および Selector を
保持します。同じ入力の組には、同じ Region または同じ意味の Failure が対応します。

### Region の領域関係

同じ Observation に属する比較可能な二つの Region には、次の五値のうち一つが対応します。

```text
RegionExtentRelation =
  | Equal
  | Contains
  | ContainedBy
  | Overlaps
  | Disjoint
```

関係は左 Region から右 Region を見た値です。引数を交換すると `Contains` と `ContainedBy` が
入れ替わり、`Equal`、`Overlaps`、`Disjoint` は維持されます。`Equal` は同値関係です。strict な
包含は非反射的、非対称、推移的です。`Overlaps` と `Disjoint` は対称です。

Core は Whole Region を含む関係を決定します。built-in Interpreter は Core 内の同じ protocol を
実装し、Extension Interpreter は `classifyRegionExtents` を通じて自身の部分 Region を比較します。
部分 Region の extent relation は、Interpreter が所有する領域意味論から得ます。

## Annotation、Reference、および Relation

### Scope と local ID

AnnotationId と ReferenceId は、正規化済み Origin を Scope とする local ID です。

```text
Scope = NormalizedOrigin
AnnotationId = Scope × LocalAnnotationId
ReferenceId  = Scope × LocalReferenceId
```

この Scope により、同じ Resource を再観測して ObservationIdentity が変わった場合も、明示情報の
local ID を継続して使用できます。特定の観測結果を要求する場合は、Origin と ObservationExpectation
を組み合わせます。

### Annotation

`Annotation` は、Region についての明示的な主張を表す意味値です。

```text
Annotation
  id: AnnotationId
  subject: RegionRef
  predicate: string
  object: RegionRef | ReferenceId | Literal
```

保存形式、保存位置、編集所有権、および抽出処理の情報は Annotation の外側に置きます。

`AnnotationOccurrence` は、一つの Annotation が実際に記載されている一件です。

```text
AnnotationOccurrence
  annotation: Annotation
  source: SourceLocation
```

同じ Annotation が複数の場所に記載されている場合、一つの意味値と複数の occurrence を保持します。

### Reference

`Reference` は、名前付きの参照先と追跡規則を表す意味値です。

```text
Reference
  id: ReferenceId
  target: RegionAddress
  binding: Pinned | Tracking | Floating
  expectations: Expectation[]
```

`Pinned` は特定の Observation expectation への一致を要求します。`Tracking` は Origin の現在状態を
再観測し、以前の ResolutionSnapshot との差を検査します。`Floating` は Origin の現在状態を解決し、
保存済み ObservationIdentity への一致を要求しません。すべての binding で Selector は正確に解決します。

`ReferenceDefinitionOccurrence` は Reference の定義が記載された一件です。

```text
ReferenceDefinitionOccurrence
  reference: Reference
  source: SourceLocation
```

`ReferenceUse` は、文書や source code 内で Reference が実際に使用された一件です。

```text
ReferenceUse
  sourceObservation: ObservationId
  sourceRegion: RegionId | WholeObservation
  sourceRange: ByteRange
  target: ReferenceId | RegionAddress
```

Reference の定義、Reference の使用、および Annotation は、それぞれ専用の型と collection で扱います。

### SourceLocation

SourceLocation は occurrence の正確な記載位置を表す閉じた直和です。

```text
SourceLocation =
  | InObservation {
      observation: ObservationId,
      locator: ByteRange | StructuredLocation,
      encoding: ObservationEncoding
    }
  | InSidecar {
      path: WorkspacePath,
      contentIdentity: ContentIdentity,
      locator: StructuredLocation,
      ownership: Authored | Derived
    }
```

`Authored` は利用者が編集する Sidecar 領域、`Derived` は Deriver が再生成する Sidecar 領域を表します。
ownership は編集権限を決めます。意味値の整合判定には scoped ID と型別の equality を使用します。

### 型別 index と Conflict

Core は Annotation と Reference を別々に整合判定します。

```text
AnnotationIndex: AnnotationId ->
  | Consistent {
      value: Annotation,
      occurrences: NonEmpty<AnnotationOccurrence>
    }
  | Conflict {
      occurrences: NonEmpty<AnnotationOccurrence>
    }

ReferenceIndex: ReferenceId ->
  | Consistent {
      value: Reference,
      occurrences: NonEmpty<ReferenceDefinitionOccurrence>
    }
  | Conflict {
      occurrences: NonEmpty<ReferenceDefinitionOccurrence>
    }
```

同じ scoped ID の意味値が一致する場合は、全 occurrence を一つの consistent entry に保持します。
意味値が異なる場合は、全 occurrence を Conflict に保持します。Graph 構築や解決が単一の意味値を
必要とする箇所では、Conflict を Diagnostic と coverage に反映します。

### Relation と workspace graph

`Relation` は、Region 間の意味的な有向 edge です。object が Region または Reference である
整合確認済み Annotation から、次の射影を決定的に構築します。

```text
Relation
  source: RegionEndpoint
  predicate: string
  target: RegionEndpoint
  evidence: NonEmpty<AnnotationOccurrence>
```

```text
subject Region --predicate--> object Region
```

ReferenceUse は、実際の参照を表す `ReferenceEdge` を構築します。

```text
ReferenceEdge
  source: RegionEndpoint
  target: ResolvedEndpoint | UnresolvedEndpoint
  use: ReferenceUse
```

Reference の定義は ReferenceIndex に、literal object を持つ Annotation は AnnotationIndex に保持します。
Workspace graph は、Relation と ReferenceEdge を型の異なる edge として保持します。

`WorkspaceGraphSnapshot` は、一回の安定した workspace 処理から構築する不変値です。

```text
WorkspaceGraphSnapshot
  observations
  sidecarSnapshots
  regions
  annotationIndex
  referenceIndex
  referenceUses
  relations
  referenceEdges
  diagnostics
  coverage
```

## Sidecar metadata

Sidecar document は、Observation に Annotation と Reference を付加する上位の宣言的 metadata file
です。primary data の形式から独立しており、workspace file、Git object、Web Resource など、任意の
Origin を対象にできます。

Sidecar document の root object は、対象を `scope.origin` で明示します。

```yaml
version: 2
scope:
  origin:
    kind: workspace
    path: data/report.json

authored:
  refs: {}
  annotations: {}

derived:
  refs: {}
  annotations: {}
```

filename は Sidecar metadata を発見するための閉じた規約に使用し、対象の決定には
`scope.origin` を使用します。これにより、同じ stem を持つ複数形式の file を独立して対象にできます。

metadata loader は Sidecar file を安定して読み、操作中の内容を固定します。

```text
SidecarSnapshot
  path: WorkspacePath
  contentIdentity: ContentIdentity
  bytes: FiniteBytes

decodeSidecar(SidecarSnapshot) -> SidecarContents | MetadataFailure

SidecarContents
  scope: Origin
  annotations: AnnotationOccurrence[]
  referenceDefinitions: ReferenceDefinitionOccurrence[]
```

SidecarSnapshot は metadata plane の固定値です。ContentIdentity は parse 対象の固定、cache の
無効化、および Patch の競合検査に使用します。

Sidecar 候補は Resource inventory の構築前に分類します。metadata loader と Core decoder が候補を
処理し、SidecarContents を対象 Origin の Observation と組み合わせます。Sidecar の件数、読み取り、
decode、および scope 解決は metadata coverage として集計します。
予約済み候補一件の処理結果は、検証済み SidecarContents または構造化された MetadataFailure の
いずれかです。

SidecarContents の構築は対象 Origin の観測結果から独立しています。対象の観測が Failure になった
場合も、metadata 内の occurrence と SourceLocation を保持し、対象 Observation の解決状態を別の
Diagnostic として記録します。同じ Scope を持つ複数の SidecarContents はすべて型別 index へ渡します。

対象 Origin の Observation に Interpreter がある場合、Sidecar 内の部分 Region selector を解決します。
Whole Observation を指す Annotation と Reference は、対象の形式に固有の Interpreter を使わずに
扱えます。Sidecar metadata は対象 Observation の identity を維持したまま、Core が利用できる明示情報を
増やします。

## Extractor

Extractor は、primary Observation に実際に記載された明示情報を抽出します。

```text
extractAnnotations(
  AnnotationExtractorIdentity,
  Observation,
  Interpretation?
) -> AnnotationExtraction | ExtractionFailure

AnnotationExtraction
  occurrences: AnnotationOccurrence[]

extractReferences(
  ReferenceExtractorIdentity,
  Observation,
  Interpretation?
) -> ReferenceExtraction | ExtractionFailure

ReferenceExtraction
  definitions: ReferenceDefinitionOccurrence[]
  uses: ReferenceUse[]
```

複数の Extractor は加算的に適用できます。Core は結果を型ごとに集約し、Sidecar decoder が作った
同じ occurrence 型とともに専用 index へ渡します。

## Auditor

Auditor は、安定した workspace snapshot、型別 index、occurrence、解決結果、および宣言的 policy を
入力として Diagnostic を返します。

```text
audit(
  AuditorIdentity,
  WorkspaceGraphSnapshot,
  AuditPolicy
) -> Diagnostic[] | AuditFailure
```

標準 Auditor は、同じ scoped ID の divergent value、壊れた Reference、stale selector、expectation
failure、inline-only、sidecar-only、および未使用 Reference を検査します。sidecar-only の許可や
各 code の severity は policy value が決定します。複数 Auditor の Diagnostic は code と location の
正規順序で集約します。

## Reference の解決と cross-interpreter graph

Reference 解決は、source と target を独立した値として扱います。

```text
Reference.target: RegionAddress
  -> normalize Origin
  -> Resource Observer dispatch
  -> target Observation
  -> exact Interpreter dispatch
  -> resolveRegion
  -> target Region | Failure
```

成功した解決は、再検証可能な値として保存できます。

```text
ResolutionSnapshot
  target: RegionAddress
  observationIdentity: ObservationIdentity
  regionFingerprint?: Fingerprint
  observedAt: Timestamp
```

target 解決の完全な入力は、target RegionAddress、target Observation、および target
InterpreterIdentity です。RegistrySnapshot から exact match で選び、独立した checked session で
target Observation を解決します。

Graph 構築は複数の Interpreter を同じ試行で使用できます。各 Observation には一意な Interpreter を
割り当て、Observation ごとの Interpretation と Extractor 結果を集約します。incoming edge は target
Origin を使って発見でき、target selector の解決状態を edge の endpoint status として保持します。

Region を指定した `related` query は、RegionExtentRelation を使って endpoint の所属を判定します。
`exact` scope は `Equal`、`contained` scope は `Equal` と selected Region から見た `Contains` を
含めます。

## Derive、Infer、および Patch

`Derive` は、すでに明示されている意味値から、別の encoding に同じ意味値を記載するための Patch を
決定的に生成します。

```text
derive(
  DeriverIdentity,
  DeriveRequest,
  WorkspaceGraphSnapshot
) -> ProposedPatch[] | DeriveFailure
```

`DeriveRequest` は、source occurrence、target Origin、target encoding、および policy を宣言値として
指定します。

```text
AnnotationOccurrence at InObservation
  -> Deriver
  -> ProposedPatch for Sidecar derived section
  -> Core apply
  -> SidecarSnapshot
  -> AnnotationOccurrence at InSidecar
```

Derive の前後で Annotation、Reference、および scoped ID は維持され、SourceLocation が増えます。
Deriver は `Derived` 領域を再生成し、`Authored` 領域の byte を保持します。

`Infer` は、明示されていない Annotation や Relation の候補を、根拠と confidence とともに生成する
別 capability です。Infer の候補は、利用者が承認した Patch によって保存表現へ書き込まれた後に
occurrence になります。

すべての workspace 変更は `ProposedPatch` を経由します。

```text
ProposedPatch =
  | Create {
      target: WorkspacePath,
      content: Bytes,
      resultingContentIdentity: ContentIdentity,
      provenance: Provenance
    }
  | Edit {
      target: WorkspacePath,
      expectedContentIdentity: ContentIdentity,
      edits: NonEmpty<TextEdit>,
      resultingContentIdentity: ContentIdentity,
      provenance: Provenance
    }
```

Core の `apply` が filesystem 書き込みを担当します。apply は canonical path、現在の ContentIdentity、
edit range の非重複、計算後の ContentIdentity、および workspace containment を検証します。publication
は atomic に行い、同じ Patch の再適用は同じ結果へ収束します。

## Extension の宣言、install、および session

### ExtensionManifest

`ExtensionManifest` は、一つの capability の意味上の契約を表す宣言値です。

```text
ExtensionManifest
  protocolVersion
  capabilityType
  capabilityIdentity
  acceptedObservationTypes
  applicability
  selectorSchemas
  resultSchemas
```

workspace は Extension identity、selector、policy などの宣言値を保持します。Host installation state
は、実行を許可した executable と manifest の対応を保持します。

### InstalledExtension と RegistrySnapshot

`InstalledExtension` は、検証済み ExtensionManifest と host の起動情報を結び付けた値です。

```text
InstalledExtension
  manifest: ExtensionManifest
  launch:
    executable: AbsolutePath
    arguments: string[]
    authority:
      | SandboxedAuthority { launchPaths: AbsolutePath[] }
      | ResourceObserverAuthority {
          originClass: ExtensionOrigin,
          launchPaths: AbsolutePath[],
          resourceReadPaths: AbsolutePath[],
          network: boolean
        }
```

`RegistrySnapshot` は、一回の操作で使用する InstalledExtension の不変な集合です。同じ capability
type、name、および version は snapshot 内で一意です。RegistrySnapshot は workspace 外の host
installation state から作り、操作全体で同じ値を使用します。

### capability ごとの dispatcher

候補数と合成規則は capability ごとに定義します。

| Dispatcher | 選択規則 | 結果の合成 |
|---|---|---|
| Resource Observer | Origin が指定する built-in または exact observer identity | 一つの Observation |
| Interpreter | ObservationType と applicability に一致する候補が一つ | 一つの Interpretation |
| Region extent | Region が保持する InterpreterIdentity に exact match | 一つの五値関係 |
| Annotation Extractor | 適用可能な全候補 | occurrence を加算 |
| Reference Extractor | 適用可能な全候補 | definition と use を型別に加算 |
| Auditor | policy で有効な全候補 | Diagnostic を加算 |
| Deriver | derive operation が明示する target と encoding | ProposedPatch を加算 |

Interpreter の候補がゼロなら unsupported coverage、二つ以上なら ambiguous dispatch Failure です。
明示 identity を持つ操作は exact match を使用します。各 dispatcher は自身の入力型、選択規則、
Failure 型、および正規化規則を所有します。

```text
dispatch(candidates) =
  | []      -> Unsupported
  | [one]   -> Selected(one)
  | many    -> Ambiguous(candidates)

execute(Selected(one)) = Success(value) | CapabilityFailure
```

CapabilityFailure は選択済み capability の実行結果として保持し、同じ dispatch decision の結果にします。

### checked session

Core は InstalledExtension の executable を shell-free の引数配列で起動し、最初に
`monika.initializeSession` を呼びます。Extension が返す protocol version、capability identity、
applicability、および schema identity を InstalledExtension の manifest と照合します。照合済み
session だけが capability method を実行します。

Extension process は initialization の中で宣言値を計算して返せます。手続きの実行許可は
InstalledExtension の launch binding が与え、手続きが返した manifest は capability を説明する
値として検証・比較します。

一つの request は、入力値、content stream、成功結果または Failure、および終了確認までを明確な
境界として持ちます。message size、nesting depth、safe integer、UTF-8、timeout、および process
終了時間には上限を設けます。stdout は protocol message、stderr は診断 log に使用します。

同じ executable は複数 capability の InstalledExtension に使用できます。各 session は選択した
一つの capability identity で初期化し、method ごとの型付き契約に従います。

Extension protocol は capability ごとに独立した method と schema を持ちます。

| Capability | Method |
|---|---|
| Resource Observer | `monika.observeResource` |
| Interpreter | `monika.interpretObservation` |
| Region resolution | `monika.resolveRegion` |
| Region extent | `monika.classifyRegionExtents` |
| Annotation Extractor | `monika.extractAnnotations` |
| Reference Extractor | `monika.extractReferences` |
| Auditor | `monika.audit` |
| Deriver | `monika.derive` |

各 method は、対応する semantic operation の入力、成功値、および operation-specific Failure を
schema 化します。

### 内容転送と隔離

ObservationType ごとの transfer adapter が、HostOwnedObservationValue を Extension protocol の
入力表現へ写します。byte-backed Observation は host-owned stream として渡します。stream は
Observation の ContentIdentity と byte 数に結び付け、連続した bounded chunk と終端 message で
転送します。構造化表現は schema identity と正規化済み value を持ち、同じ上限と検証規則に従います。
Extension は受信した内容を自身の memory または許可された scratch space で処理します。

Interpreter、Extractor、Auditor、および Deriver の sandbox は、protocol channel、read-only の
入力 stream、および bounded scratch space を公開します。Resource Observer は、対応する Origin
class の観測に必要な authority を明示的に付与された session で実行します。Extension が生成した
Observation content は host-owned storage へ固定してから、ほかの capability へ渡します。

Resource Observer の byte-backed 出力は、request ID に結び付いた extension-to-host stream として
転送します。Core は chunk の連続性、宣言された byte 数、ContentIdentity、および ObservationIdentity
との対応を検証し、完全な値を固定した時点で Observation を受理します。大きな出力も同じ bounded
stream 契約で host-owned storage へ移します。

workspace への書き込み権限は Core の apply 境界に集約します。これにより、解釈、検査、導出、および
適用を独立して再実行・監査できます。

## Failure、Diagnostic、および coverage

各 effectful operation は、成功値または operation 固有の Failure を返します。

```text
Failure
  operation: OperationIdentity
  code: StableCode
  message: string
  data?: NormalizedValue
```

Extension の JSON-RPC error、Extension が返した capability Failure、host の I/O Failure、timeout、
decode Failure、および invariant violation は、発生した operation と code を保持した値になります。
CLI は Failure を `CommandResult` または query result の Diagnostic へ写します。

command entry point は、入力検証、effectful operation、および invariant 検査の結果から必ず result
envelope を構築します。process exit class は result status から導出し、machine-readable stdout は
同じ result を表します。実装例外は command boundary で `internal-failure` へ変換し、operation と
安定した code を保持します。

候補選択、解釈、抽出、metadata decode、selector 解決、および Region 比較は、それぞれの Failure を
結果へ保持します。Graph と query は、成功した範囲と未完了の範囲を coverage で表します。

```text
Coverage
  primaryResources
  observed
  interpreted
  unsupported
  failed
  metadataDiscovered
  metadataDecoded
  metadataFailed
  complete
```

空の query result は、指定した coverage 内で一致する明示的 edge が観測されなかったことを表します。
完全性は `complete` と各件数で判断します。

## 安定した workspace 処理

workspace scan は、canonical path 順の primary Resource inventory と Sidecar metadata inventory を
構築します。各 file は retained directory handle から開き、symbolic link や reparse point の境界を
検査し、読み取り前後の file identity と時刻を比較します。

WorkspaceGraphSnapshot の構築は、開始時 inventory、各固定済み Observation、各 SidecarSnapshot、
RegistrySnapshot、および capability version の組に基づきます。構築完了時に inventory を再確認し、
変更があれば試行全体を新しい値で再実行します。確定した snapshot は、単一の整合した試行から得た
値だけを含みます。

cache と index は、ObservationIdentity、Sidecar ContentIdentity、capability identity、schema version、
および policy identity から validity を判定できる派生物です。結果の意味は一次入力と capability
identity から決まり、cache は同じ値の構築を高速化します。

## CLI の責務

最初に固定する command の責務は次のとおりです。

| Command | 責務 |
|---|---|
| `monika scan` | primary Resource と Sidecar metadata を分類し、Observation inventory と metadata coverage を返す |
| `monika inspect` | 一つの Observation、その Interpretation、typed occurrences、および対応 Sidecar metadata を返す |
| `monika resolve` | RegionAddress または Reference を現在の Observation と Region へ解決する |
| `monika check` | Conflict、壊れた参照、stale selector、sidecar-only、inline-only などを診断する |
| `monika derive` | 明示済み occurrence から ProposedPatch を生成する |
| `monika apply` | ProposedPatch を検証し、workspace へ atomic に適用する |
| `monika capabilities` | built-in と RegistrySnapshot の capability identity と適用条件を列挙する |
| `monika extension test` | manifest、session initialization、method、Failure、および終了条件を検査する |
| `monika related` | WorkspaceGraphSnapshot から incoming、outgoing、および internal edge を問い合わせる |
| `monika read` | 一つの Observation と関連する明示情報を Agent が直接読める形で返す |

すべての machine-readable result は schema version、status、Diagnostic、coverage、および正規化済み
payload を持ちます。collection の順序は意味値の正規順序から決定します。

## 実装構造

参照実装は、純粋な semantic core と effectful adapter を分離します。

```text
Semantic core
  validated values
  smart constructors
  normalization
  equality and reconciliation
  graph construction
  patch algebra

Effectful adapters
  filesystem observation
  extension process runtime
  registry loading
  metadata loading
  network-backed Resource Observers
  atomic patch application

Specification layer
  JSON Schema
  protocol methods
  diagnostic code catalog
  golden results
  conformance fixtures
  idempotency and parity tests
```

内部状態は immutable value として受け渡し、状態遷移は入力値から出力値を作る関数として表します。
外部境界で受け取る JSON、YAML、path、Extension response、および Patch は、検証済み semantic value
へ変換してから Core へ渡します。

後続の高速実装は、参照実装の内部 module を移植する代わりに、Specification layer が固定する
正規形、Failure、Diagnostic、Patch、graph、workspace transition、および golden result を再現します。

## 中核不変条件

1. 同じ正規化済み Origin は、同じ Resource を指そうとする値として比較します。
2. ObservationIdentity は ObservationType を含み、同じ identity は同じ観測可能な値を表します。
3. 一回の処理で使用する Observation と SidecarSnapshot は固定値です。
4. すべての Observation は Whole Region を持ちます。
5. 一つの Region は一つの Observation に属します。
6. 部分 Region は InterpreterIdentity、ObservationIdentity、および Selector の組で解決します。
7. Region の extent 関係は五値の代数に従います。
8. Annotation と Reference は保存形式と保存位置から独立した意味値です。
9. AnnotationOccurrence、ReferenceDefinitionOccurrence、および ReferenceUse は専用の型で保持します。
10. Sidecar は Observation に明示情報を付加する metadata plane の入力です。
11. Sidecar の対象は root の Scope Origin で決定します。
12. 同じ scoped ID の異なる意味値は、全 occurrence を持つ Conflict になります。
13. Authored と Derived は編集所有権として機能します。
14. Derive は明示済みの意味値を維持し、Infer は根拠付き候補を生成します。
15. workspace の変更は ProposedPatch と Core apply を経由します。
16. RegistrySnapshot は一回の操作中に不変です。
17. capability ごとの dispatcher が候補数、合成規則、および Failure を決定します。
18. cross-interpreter resolution は target の exact InterpreterIdentity と独立 session を使用します。
19. Extension は host-owned input を処理し、Core は Observation と workspace の所有権を保持します。
20. すべての effectful operation は成功値または構造化された Failure を返します。
21. query result は明示情報と coverage を同時に返します。
22. cache と index は identity と version から再構築できる派生物です。
23. 観測可能な値は schema、golden test、および parity test で固定します。

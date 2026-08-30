# Annotation、Reference と保存位置のモデル

## この文書の目的

Monika は、同じ Annotation や Reference を Markdown、source comment、補助的な YAML
file など、複数の表現に記載できるようにします。この機能には、意味値と、その値が
実際に記載された位置を分けるモデルが必要です。

この文書は、その概念と内部モデルを説明します。特定の OCaml module、現在の JSON
Schema、または一時的な実装手順を説明する文書ではありません。参照実装と後続実装は、
ここで定める区別を、それぞれの言語に自然な型で実現します。

この文書は規範的なモデルです。schema version 11 と参照実装は、Annotation と保存位置の
分離、型別 occurrence、Origin-scoped ID、および Sidecar metadata plane をこのモデルに
従って実装します。Sidecar file は独立した Observation ではなく、固定済み
`SidecarSnapshot`、metadata failure、および metadata coverage として扱います。

## 用語

この文書では、独自の総称として `Declaration` という型を導入しません。Annotation の
記載、Reference の定義、および Reference の使用は、異なる意味と異なる同値条件を持つため
です。共通する保存位置だけを `SourceLocation` として再利用します。

| 用語 | この文書での意味 |
|---|---|
| `Annotation` | Region についての明示的な主張を表す意味値 |
| `AnnotationOccurrence` | 一つの Annotation が、primary Observation または Sidecar metadata に実際に記載されている一件 |
| `Reference` | 名前付きの参照先、binding、および expectation を表す意味値 |
| `ReferenceDefinitionOccurrence` | 一つの Reference 定義が実際に記載されている一件 |
| `ReferenceUse` | 文書中で Reference が実際に使用された一件 |
| `SourceLocation` | primary Observation または固定済み SidecarSnapshot 内の正確な位置 |
| `Scope` | local AnnotationId と ReferenceId の名前空間になる正規化済み Origin |
| `Conflict` | 同じ scoped ID に異なる意味値が記載され、単一の値を選べない状態 |
| Sidecar document | Observation を補強する、上位の宣言的 metadata file |
| `SidecarSnapshot` | Sidecar file を一回の操作のために安定して読み、path と ContentIdentity と内容を固定した値。Observation ではない |

`Occurrence` は、単なる検出候補を意味しません。primary Observation または SidecarSnapshot の
具体的な位置に存在する、検証済みの一件を意味します。

## 中心原則

Annotation と Reference は意味値です。保存形式と保存位置は意味値自身に含めません。

```text
Annotation
  何について、どの predicate で、何を主張しているか

AnnotationOccurrence
  その Annotation が、primary Observation または Sidecar metadata のどこに記載されているか

SidecarDocument
  Observation に Annotation と Reference を付加する上位 metadata
```

Monika は Annotation database を持ちません。inline や source comment は Resource の
Observation から読み取り、Sidecar は metadata file の SidecarSnapshot から読み取ります。
どちらも元の byte から再構築しますが、同じ意味階層には置きません。

したがって、保存形式ごとに別の Annotation を作ってから、優先順位で一つへ潰してはいけません。
同じ ID の記載内容が異なるなら、それは一つの Annotation ではなく Conflict です。

## Resource、Origin、Observation

基礎的な定義は [`implementation-concept.md`](implementation-concept.md) と同じです。
ここでは保存位置との関係を理解するために必要な部分を説明します。

### Resource

Resource は、Monika が状態を観測しようとする対象です。Resource は byte 列、file object、
Observation、または Monika 内部の record と同義ではありません。

同じ対象へ繰り返し観測を試みることに意味があるとき、その対象を一つの Resource と考えます。
Resource の状態は変化でき、消失や一時的な観測失敗も許します。

例は次のとおりです。

- 一つの workspace と canonical path で指定された file entry
- Git repository 内の path と任意の revision 指定
- 一つの Web URL が指そうとする対象
- 一つの GitHub Issue
- 継続的に増える実験ログ

Resource 自体に、有限性、不変性、byte 表現、または Core が比較できる identity は要求しません。
Resource は protocol で受け渡す値でもありません。

workspace に存在するすべての file を、Monika の意味モデル上の Resource として列挙するわけでは
ありません。Sidecar として予約された metadata file は Resource inventory へ入れず、metadata
loader が別に読みます。filesystem 上で同じ regular file であることは、意味上の役割まで同じに
する理由にはなりません。

### Origin

Origin は、Resource を再び指そうとする正規化可能な値です。取得手順ではありません。

同じ正規化済み Origin は、同じ Resource を指そうとしているものとして扱います。異なる
Origin が現実には同じ Resource を指す可能性があっても、Core はそれを推測して統合しません。
Monika は一般的な `ResourceId` や Resource equality を持ちません。

Origin が有効でも、Resource の不存在、権限、network、認証、または一時的な状態によって
観測は失敗できます。Origin の存在は Observation の存在を意味しません。

### Observation

Observation は、Origin が指そうとする Resource を一回観測し、その操作で固定して扱える形に
した有限の結果です。

```text
observe(origin)
  -> Observation
  |  Failure
```

同じ Origin から、異なる時点に異なる Observation を得られます。Resource と Origin が同じでも、
内容が変われば ObservationIdentity は変わります。byte 列は Observation の一表現であり、
すべての Observation には要求しません。

```text
Resource
  時間とともに状態が変わり得る観測対象

Origin
  その Resource を再び指そうとする比較可能な値

Observation
  一回の操作で固定された有限の観測結果
```

## Scope と scoped ID

`Scope` は、AnnotationId と ReferenceId の local ID が属する正規化済み Origin です。
Resource 自体や ObservationIdentity ではありません。

```text
AnnotationId = Scope(normalized Origin) × LocalAnnotationId
ReferenceId  = Scope(normalized Origin) × LocalReferenceId
```

Scope を Origin に置くことで、primary Resource の内容が変わり、新しい Observation になっても、
同じ local ID を継続して使用できます。操作中は Scope の Origin を観測し、その操作の固定済み
Observation と結び付けます。Whole Observation の address は Interpreter を持ちません。部分 Region
の address は exact InterpreterIdentity を必須とし、その固定済み Observation に対して解決します。

特定の ObservationIdentity だけへ値を固定する必要がある場合は、Origin と identity expectation
を別々の値として明示します。Origin と ObservationIdentity を一つの identity にまとめません。

Scope の Origin を観測できない場合も、Sidecar 内の記載は失われません。Core は各 occurrence と
SidecarSnapshot 内の SourceLocation を保持したまま、対象 Observation が未解決であることと観測
Failure を返します。存在しない Observation を捏造せず、記載を空の結果へ置き換えません。

## 意味値と保存位置

### Annotation

Annotation は、Region についての明示的な主張です。

```text
Annotation
  id: AnnotationId
  subject: RegionRef
  predicate: string
  object: RegionRef | ReferenceId | Literal
```

Annotation には次を含めません。

- Markdown、source comment、YAML などの encoding
- 記載元 Observation の byte range
- Sidecar path
- Authored または Derived という編集所有権
- decoder 名を表す自由形式文字列

AnnotationId の一致は比較の開始条件であり、内容一致の代わりではありません。同じ ID で
subject、predicate、または object が異なる場合は Conflict です。

### AnnotationOccurrence

AnnotationOccurrence は、Annotation と SourceLocation の組です。

```text
AnnotationOccurrence
  annotation: Annotation
  source: SourceLocation
```

同じ Annotation が三か所に記載されている場合、Annotation は一つですが
AnnotationOccurrence は三つあります。三つの記載位置を失わずに保持します。

### Reference

Reference は、名前付きの参照先を表す意味値です。

```text
Reference
  id: ReferenceId
  target: RegionAddress
  binding: pinned | tracking | floating
  expectations: Expectation[]
```

Expectation は ObservationIdentity、ContentIdentity、schema 付き revision、または schema 付き
Region fingerprint の閉じた直和です。RegionAddress の単一 expectation は address 自体の不変条件であり、
すべての binding で解決時に検証します。Reference の expectations は Pinned 固有です。Pinned は
address または Reference に少なくとも一つの expectation を必要とし、Tracking と Floating は
Reference 側に pinned expectation を保持しません。

Tracking は前回の ResolutionSnapshot が渡された場合に ObservationIdentity と Region fingerprint の
差を報告します。Floating は現在の値を解決しますが、保存済み ObservationIdentity との一致を
要求しません。

### ReferenceDefinitionOccurrence

ReferenceDefinitionOccurrence は、一つの Reference 定義と、その SourceLocation の組です。

```text
ReferenceDefinitionOccurrence
  reference: Reference
  source: SourceLocation
```

Sidecar に未使用の Reference を定義できます。一つの Reference をinlineとSidecarの両方に
定義することもできます。内容が一致するかどうかはReference専用の整合判定で確認します。

### ReferenceUse

ReferenceUse は、Reference が実際に使用された一件です。Reference の定義とは別の値です。

```text
ReferenceUse
  sourceObservation: ObservationId
  sourceRegion: RegionId | WholeObservation
  sourceRange: ByteRange
  target: ReferenceId | RegionAddress
```

一つの構文が Reference の定義と使用を兼ねる場合も、Extractor は
ReferenceDefinitionOccurrence と ReferenceUse を別々に返します。ReferenceUse は重複定義の
整合判定へ入れず、実際の使用一件として保持します。

## SourceLocation

SourceLocation は、Annotation または Reference 定義が記載された正確な位置を示します。
記載先には primary Observation と Sidecar metadata という異なる種類があるため、両者を
同じ field の値で曖昧に表しません。

```text
SourceLocation =
  | InObservation {
      observation: ObservationId,
      locator: ByteRange | StructuredLocation,
      encoding: MarkdownInline | SourceComment | ...
    }
  | InSidecar {
      path: WorkspacePath,
      contentIdentity: ContentIdentity,
      locator: StructuredLocation,
      ownership: Authored | Derived
    }
```

`InObservation.observation` は、対応する ObservationIdentity を持つ固定済み primary Observation
を結果内で参照します。`InSidecar` の path、ContentIdentity、および locator は、その操作で
固定した SidecarSnapshot 内の位置を示します。いずれも内容変更後の値へ同じ位置を流用しません。

`ByteRange` は inline comment などに使います。`StructuredLocation` は YAML record など、
構造上の位置も必要な場合に使います。後続実装も同じ場所を識別できる正規形を定めます。

`ownership` は Sidecar 内の記載について、どの処理がその byte を編集してよいかを示します。
意味上の優先順位ではありません。primary Observation にある inline や source comment は
利用者が所有する記載であり、Core が derive の出力として上書きする対象にはしません。

- `Authored` は利用者が所有し、Monika が自動編集しない位置です。
- `Derived` は Deriver が再生成できる位置です。

Authored と Derived に同じ scoped ID の異なる値がある場合も Conflict です。Authored を
意味上の正解として自動採用しません。

## 型ごとの抽出結果

Extractor は異種の値を `Declaration[]` として返しません。Annotation と Reference には、
別の結果型と別の整合規則があります。

```text
AnnotationExtraction
  occurrences: AnnotationOccurrence[]

ReferenceExtraction
  definitions: ReferenceDefinitionOccurrence[]
  uses: ReferenceUse[]
```

これらは primary Observation に適用する Extractor の結果型です。同じ primary Observation に
複数の Annotation Extractor または Reference Extractor が適用されることを許します。それらの
結果は型ごとに集めます。Sidecar metadata decoder も同じ occurrence 型を構築しますが、Observation
Extractor を装って呼び出すわけではありません。Extractor の順序、scan 順、および filename は
意味上の優先順位になりません。

## 型ごとの整合判定

Annotation と Reference の整合判定は、別の純粋関数として行います。両者を一つの汎用
reconciliationへ渡しません。

概念的な Annotation index は次の形です。

```text
AnnotationIndex: AnnotationId ->
  | Consistent {
      annotation: Annotation,
      occurrences: NonEmpty<AnnotationOccurrence>
    }
  | Conflict {
      occurrences: NonEmpty<AnnotationOccurrence>
    }
```

Reference index は ReferenceId をkeyにして、ReferenceDefinitionOccurrenceを同様に比較します。
ただし、Referenceの等価性はtarget、binding、expectationsによって決まり、Annotationの
等価性とは別です。

異なる ID の値を、構造が似ているという理由で統合しません。その処理は明示 ID の整合判定
ではなく、別の infer または整理操作です。

Conflict がある場合、近い値、先に読んだ値、inline側、Sidecar側などを選びません。Conflictと
全 occurrence を結果に残します。単一の値が必要なgraph処理は、そのIDからedgeを作らず、
Diagnosticとcoverageへ反映します。

## Annotation と Relation

Annotation は保存可能な明示的主張です。Relation は、その主張をgraphで問い合わせるための
意味的な射影です。

AnnotationのobjectがRegionまたはReferenceである場合、Coreは整合確認済みAnnotationから
`subject --predicate--> object`というRelationを決定的に構成できます。literal objectを持つ
Annotationは、必ずしもgraph edgeにはなりません。

RelationをAnnotationとは別の正本として保存しません。推測されたRelationはinferの結果であり、
明示Annotationからの射影とは区別します。

## Annotation はどのように保存されるか

Core が永続化する Annotation object はありません。保存されるのは、Annotation の記載を encode
した file の byte です。ただし、その file が Monika の意味モデルで果たす役割は二種類あります。

```text
primary Resource の file
  HTML comment や source comment の byte
  -> Resource Observer が Observation として固定する

Sidecar metadata file
  YAML record の byte
  -> metadata loader が SidecarSnapshot として固定する
```

`inspect` は primary Resource から Observation を、Sidecar metadata file から SidecarSnapshot を
作り、それぞれから AnnotationOccurrence や ReferenceDefinitionOccurrence を再構築します。
`CommandResult` や workspace graph に含まれる意味値は、その操作で構築した結果であり、次回へ
持ち越す正本ではありません。

Annotation を新しい場所へ保存するときも、database へ insert しません。Deriver が対象 encoding
の byte を作る ProposedPatch を返し、Core が apply します。その後の操作では、primary file なら
新しい Observation を、Sidecar file なら新しい SidecarSnapshot を作ります。

cache や index を導入する場合も再構築可能な派生物とし、正本にはしません。primary Observation
由来の結果は ObservationIdentity と capability version で、Sidecar 由来の結果は ContentIdentity
と Sidecar format version で無効化します。

## Provenance と SourceLocation

SourceLocationは「この記載をどこから読んだか」を示します。Provenanceは、値やPatchがどの
変換によって導かれたかという因果関係です。二つを自由形式文字列で兼用しません。

Markdown inline から Sidecar の Derived record を生成する場合、Sidecar record の SourceLocation
は、生成後に読み直した SidecarSnapshot 内の位置です。Patch の provenance は、入力
AnnotationOccurrence と Deriver identity です。

単にfileから読み取ったAnnotation自身に、変換履歴は必要ありません。

## Sidecar document

Sidecar document は、Observation に関する Annotation と Reference を付加する宣言的な metadata
file です。primary Resource と同列の観測対象ではなく、Observation を解釈する入力でもありません。
設定 file が処理対象の data より上位にあるのと同様に、Sidecar は Observation について追加で
明示されている事実を Core へ与える metadata plane に属します。

Sidecar は次のいずれでもありません。

- Annotation そのもの
- Annotation の唯一の正本
- mutable database
- Monika の Resource inventory に含める Resource
- Observation または Interpretation
- primary Observation の Interpreter
- procedure を記述する設定file

一回の操作中に file の内容が変化しても結果を混在させないため、metadata loader は Sidecar file
を安定して読み、次の値を作ります。この固定は再現性のための読み取り規則であり、Sidecar を
Observation に分類することを意味しません。

```text
SidecarSnapshot
  path: WorkspacePath
  contentIdentity: ContentIdentity
  bytes: FiniteBytes
```

ここで ContentIdentity は、同じ操作内で parse 対象を固定し、Patch の競合を検出するための byte
identity です。Sidecar file を Resource にしたり、SidecarSnapshot を ObservationIdentity の対象に
したりする意味は持ちません。

Sidecar decoder は SidecarSnapshot を次の型へ decode します。

```text
SidecarContents
  scope: Origin
  annotations: AnnotationOccurrence[]
  referenceDefinitions: ReferenceDefinitionOccurrence[]
```

各 occurrence の SourceLocation は `InSidecar` であり、元の SidecarSnapshot を path と
ContentIdentity で指します。AnnotationId と ReferenceId の Scope は、Sidecar document 自身の
top-level `scope.origin` です。

全体のデータフローは次のようになります。

```text
primary plane
  Origin -> observe -> Observation -> Interpreter / Extractor -----+
                                                                  |
metadata plane                                                    v
  Sidecar file -> stable read -> SidecarSnapshot -> decoder -> typed indexes
                                                                  |
                                                                  v
                                                        audit / resolve / graph
```

Sidecar file を Resource Observer へ渡したり、SidecarSnapshot を Interpreter や Observation
Extractor へ dispatch したりしません。Resource inventory、Observation coverage、および未対応形式の
集計にも Sidecar を含めません。Sidecar 自身へさらに Sidecar を付ける再帰も導入しません。

Sidecar として予約された file を metadata loader が読み取れない場合、または schema に従って
decode できない場合は、metadata の Failure または Diagnostic を返します。その file を未知形式の
primary Resource として再分類する fallback は行いません。

### 対象の関連付け

Sidecar の対象を filename の stem から推測しません。`report.md` と `report.json` が同時に存在する
場合、`report.annotations.yaml` という名前だけでは対象を確定できないためです。標準 Deriver は
primary filename 全体へ予約接尾辞を追加し、それぞれ `report.md.annotations.yaml` と
`report.json.annotations.yaml` を生成します。ただし、この命名は衝突しない編集先を決める規則であり、
対象を識別する意味値ではありません。

Sidecar YAML 自身の root object に Scope の Origin を記録します。Sidecar v2 の wire schema
は、この root shape を固定します。

```yaml
version: 2
scope:
  origin:
    kind: workspace
    path: report.json

authored:
  refs: {}
  annotations: {}

derived:
  refs: {}
  annotations: {}
```

filename は Sidecar 候補を発見し、metadata file と primary file を役割分けする閉じた規約には
利用できます。ただし、filename は対象の Resource を指定しません。Core は候補を SidecarSnapshot
として固定して decode した後、`scope.origin` から対象を確定します。同じ Scope を持つ Sidecar が
複数ある場合も、scan 順や filename で一つを選びません。全 occurrence を型別の整合判定へ渡します。

候補の分類は Resource inventory を作る前に行います。予約された Sidecar 名と format の正確な規則は
wire specification で閉じて定め、任意の YAML file を推測で Sidecar にしません。

### primary形式に依存しないこと

Sidecar decoder は primary Observation の形式に依存しません。JSON、Rust source、Parquet、
未知形式の blob など、どの Origin も Scope にできます。

primary Observation に Interpreter がなくても、Sidecar 内の AnnotationOccurrence と
ReferenceDefinitionOccurrence は保持します。Whole Observation を指す subject は Core だけで
扱えます。部分 Region の address は exact InterpreterIdentity を必ず記録します。対応する
Interpreter が RegistrySnapshot に存在しなければ invalid selector として報告します。Sidecar
metadata は Observation の内容や ObservationIdentity を変更せず、
その Observation に関して Core が利用できる明示情報を増やします。

## Interpreter と Extractor

InterpreterとExtractorの責務は次のように分けます。

```text
Interpreter
  Observation の Region 構造を解釈する
  Selector を解決する
  Region の同値・包含・重なりを判定する

Annotation Extractor
  AnnotationOccurrence を返す

Reference Extractor
  ReferenceDefinitionOccurrence と ReferenceUse を返す
```

Extractorは必要に応じてInterpreterが確定したRegionを参照できます。この依存関係はworkspace設定の
pipelineにはせず、Core protocolの型付き依存関係として固定します。

一つのObservationに適用するInterpreterは一意でなければなりません。複数候補はdispatch failure
です。Extractorは複数を加算的に実行できますが、AnnotationとReferenceの結果を異種の配列へ
まとめません。

Sidecar decoder は Observation に適用する capability ではなく、Core の metadata decoder です。
一回の parse で AnnotationOccurrence と ReferenceDefinitionOccurrence の両方を構築できます。
実装を一回にすることと、出力を一つの抽象型へまとめることは別です。将来、外部 extension が
独自の Sidecar format を扱う必要が生じた場合も、Observation Extractor を流用せず、独立した
Metadata Decoder capability として設計します。

同じ Extension executable が Interpreter、Annotation Extractor、Reference Extractor の複数
capability を実装することはできます。ただし、Core は capability ごとの入力型に従って dispatch
し、SidecarSnapshot を Observation と偽って渡しません。

`Interpretation`はAnnotationの保存容器やcapability出力の寄せ集めではありません。一つの
Interpreterが固定済みObservationに与えたRegion構造と、Regionを解決・比較する意味を表します。
Core は Interpretation、primary Observation から抽出した occurrence、SidecarContents、
ReferenceUse を型別の index へ集め、workspace-level の結果を作る段階で組み合わせます。

## Derive、Infer、Apply

Deriveは、既に存在するoccurrenceと同じ意味値を、別のencodingへ記載するProposedPatchを
決定的に生成します。

```text
AnnotationOccurrence at InObservation
  -> derive
ProposedPatch for Sidecar Derived section
  -> apply
SidecarSnapshot を読み直す
  -> AnnotationOccurrence at InSidecar
```

Deriveの前後でAnnotationとscoped IDは変わりません。新しいSourceLocationが増えます。

Infer は、明示されていない Annotation や Relation を推測する別処理です。Infer の候補は、primary
Resource の内容または Sidecar metadata file へ実際に記載されるまで AnnotationOccurrence では
ありません。保存する場合は利用者が承認する Patch などの明示境界を通します。

DeriverとExtensionはworkspaceを直接変更しません。ProposedPatchを返し、実際の書き込みはCoreの
`apply`だけが行います。

## Audit と query

Auditorは、型別index、occurrence、およびConflictを検査します。

- `inline-only`: policyが期待するSidecar上のAnnotationOccurrenceがない
- `sidecar-only`: policyが期待するinline上のAnnotationOccurrenceがない
- `divergent`: 同じAnnotationIdまたはReferenceIdのoccurrenceが異なる意味値を持つ
- `stale-selector`: 記載されたRegionAddressが現在のObservationで解決しない

Sidecar-onlyはそれ自体を不正としません。severityはpolicyが決めます。

Workspace graphは、整合確認済みAnnotationとReference、および各ReferenceUseから構築します。
Conflictを片側へ解決してedgeにしません。未解決selectorや不完全なcapability coverageも、空の
query resultへ置き換えません。

Observation coverage は primary Resource だけを母集団にします。Sidecar の不存在、読み取り失敗、
decode 失敗、および対象 Origin の未解決は、Observation coverage に混ぜず、metadata coverage と
明示的な Failure または Diagnostic として報告します。

## 例

`report.json`を理解するInterpreterがない一方、Sidecarに次が記載されている場合を考えます。

- `report.json`全体をsubjectとするAnnotation一件
- 実験ログを指すReference定義一件
- AnnotationのobjectとしてそのReferenceIdを使う記載

Core の metadata loader は SidecarSnapshot を固定し、AnnotationOccurrence と
ReferenceDefinitionOccurrence を読み取ります。これは `report.json` の Observation とは別の
上位入力です。subject が Whole Observation なら、JSON 専用 Interpreter がなくても扱えます。
JSON 内の特定 object を Extension selector で指す場合は、対応 Interpreter が導入されるまで
未解決です。どちらの場合も occurrence 自体は保持します。

後からinlineに同じAnnotationIdの記載が追加され、意味値が一致すれば、AnnotationIndexは一つの
Annotationと二つのAnnotationOccurrenceを保持します。predicateなどが異なればConflictとなり、
一方をfallbackとして選びません。

## 不変条件

参照実装と後続実装は、少なくとも次を維持します。

1. AnnotationとReferenceは保存形式や保存位置をfieldに持たない。
2. AnnotationOccurrenceは一つのAnnotationと一つのSourceLocationを持つ。
3. ReferenceDefinitionOccurrenceは一つのReferenceと一つのSourceLocationを持つ。
4. ReferenceUseをReference定義やAnnotationと同じ配列へ入れない。
5. SourceLocation は、固定済み primary Observation または固定済み SidecarSnapshot の位置を、
   閉じた二種類の値として指す。
6. Sidecar は Resource inventory、Observation、Interpreter dispatch、および Observation coverage に
   入れない。
7. Sidecar の Scope は Sidecar 自身の root object に Origin として明示する。
8. Sidecar metadata は対象 Observation の内容と ObservationIdentity を変更しない。
9. filename、scan 順、Extractor 順で意味上の優先順位を作らない。
10. 予約された Sidecar の読み取りまたは decode に失敗しても、primary Resource へ fallback しない。
11. 同じ scoped ID の異なる意味値は Conflict とし、片側を自動採用しない。
12. Authored と Derived は編集所有権であり、意味上の優先順位ではない。
13. primary 形式が未対応でも Sidecar 内の occurrence を捨てない。
14. Derive は意味値を変えず、Infer と区別する。
15. 書き込みは ProposedPatch と Core の apply を経由する。

この分離により、保存形式を増やしてもAnnotationとReferenceの意味は変わりません。また、実装上
同じparserで複数種類を抽出しても、異なる意味値を一つの汎用collectionへ押し込まずに済みます。

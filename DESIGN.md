# 設計説明

## 中核モデル

このシステムは、以下のモデルを中核にします。

```text
Artifact
  情報を含む成果物。Markdown、ソースコード、JSONL、ログ、Web 取得結果、PDF、未知形式の blob など。

Region
  Artifact の中の部分領域。段落、見出し、関数、型、行、セル、JSON Pointer、byte range など。

Reference
  Region を指すための値。固定参照、追跡参照、浮動参照を区別する。

Annotation
  Region に付与される情報。inline link、source comment、sidecar entry などから得られる。

Relation
  Region と Region、または Region と Reference の意味的関係。

Snapshot
  ある時点で Reference や Region を解決した結果。変更検知と再検証に使う。

Diagnostic
  不整合、壊れた参照、古い selector、重複などの診断。

Patch
  ファイルを変更するための編集案。extension は直接書き込まず、Patch を返す。
```

## 抽象スキーマ

以下は概念スキーマです。実装時には JSON Schema として固定します。

```ts
type ArtifactDescriptor = {
  id: string;
  origin: ArtifactOrigin;
  mediaType?: string;
  contentIdentity: ContentIdentity;
  capabilities?: CapabilitySummary;
};

type ArtifactOrigin =
  | { kind: "workspace"; path: string }
  | { kind: "git"; repo: string; rev?: string; path: string }
  | { kind: "web"; url: string }
  | { kind: "generated"; name: string }
  | { kind: "external"; uri: string };

type ContentIdentity = {
  hash?: string;
  size?: number;
  gitBlob?: string;
  etag?: string;
  lastModified?: string;
};

type RegionDescriptor = {
  id: string;
  artifact: string;
  selector: unknown;
  interpreter: string;
  summary?: string;
  range?: TextRange;
  fingerprint?: Fingerprint;
};

type ReferenceRecord = {
  id: string;
  target: RegionAddress;
  binding: Binding;
  expect?: Expectation[];
  provenance?: Provenance[];
};

type RegionAddress = {
  artifact: ArtifactAddress;
  selector?: unknown;
  interpreter?: string;
};

type ArtifactAddress = {
  origin: ArtifactOrigin;
};

type Binding =
  | { mode: "pinned" }
  | { mode: "tracking" }
  | { mode: "floating" };

type AnnotationRecord = {
  id: string;
  subject: RegionRef;
  predicate: string;
  object: RegionRef | ReferenceRef | LiteralValue;
  provenance: Provenance[];
  materialization: Materialization[];
};

type Materialization =
  | { surface: "markdown-inline"; artifact: string; range: TextRange }
  | { surface: "source-comment"; artifact: string; range: TextRange }
  | { surface: "sidecar"; artifact: string; path?: string }
  | { surface: "generated-index"; artifact: string };

type ResolutionSnapshot = {
  target: RegionAddress;
  resolvedAt: string;
  artifactIdentity: ContentIdentity;
  regionFingerprint?: Fingerprint;
  display?: DisplayValue;
};

type Diagnostic = {
  severity: "info" | "warning" | "error";
  code: string;
  message: string;
  artifact?: string;
  region?: string;
  annotation?: string;
  range?: TextRange;
  suggestedFixes?: ProposedPatch[];
};

type ProposedPatch = {
  id: string;
  target: ArtifactOrigin;
  edits: TextEdit[];
  reason: string;
  provenance: Provenance;
};
```

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
  derive や check が返した Patch を安全に適用する。

monika capabilities
  現在利用可能な capability を列挙する。

monika extension test
  extension が契約を満たしているか検査する。
```

## derive と infer の区別

`derive` と `infer` は分けます。

`derive` は、既に明示された情報から別表現を導く操作です。原則として決定的であり、冪等です。

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
    mediaTypes?: string[];
    pathGlobs?: string[];
  };
  schemas?: {
    selector?: string;
    annotation?: string;
    options?: string;
  };
};

interface Interpreter {
  describe(): CapabilityDescriptor;

  canInterpret(artifact: ArtifactDescriptor): Promise<Applicability>;

  listRegions(artifact: ArtifactHandle): Promise<RegionDescriptor[]>;

  resolveSelector(
    artifact: ArtifactHandle,
    selector: unknown
  ): Promise<ResolvedRegion>;

  fingerprintRegion(
    artifact: ArtifactHandle,
    selector: unknown
  ): Promise<Fingerprint>;

  renderRegion?(
    artifact: ArtifactHandle,
    selector: unknown
  ): Promise<DisplayValue>;
}

interface AnnotationExtractor {
  describe(): CapabilityDescriptor;

  extractAnnotations(
    artifact: ArtifactHandle
  ): Promise<AnnotationCandidate[]>;
}

interface Deriver {
  describe(): CapabilityDescriptor;

  derive(
    input: DeriveInput
  ): Promise<DeriveOutput>;
}

type DeriveOutput = {
  patches: ProposedPatch[];
  diagnostics: Diagnostic[];
};
```

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

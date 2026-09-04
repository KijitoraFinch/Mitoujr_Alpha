# 実装コンセプト適合表

この文書は、[`implementation-concept.md`](implementation-concept.md) の中核不変条件を、
参照実装、外部契約、および検査へ対応付けます。機能の意味は実装ファイルではなく同文書が
規定します。この表は、実装の存在だけでなく、外部境界で同じ性質を再検査できることを示します。

## 中核不変条件

| 番号 | 参照実装の根拠 | 外部契約と検査の根拠 |
|---:|---|---|
| 1 | `Origin` が全 variant の検証、正規化、および比較を所有します。Extension locator は `Normalized_value` に固定します。 | command-result と Sidecar schema が Origin を閉じた直和として表し、semantic contract が正規形を検査します。 |
| 2 | `Observation_identity` は `Observation_type` と stable key を不可分に保持します。`Observation` の constructor が表現との対応を検証します。 | `observation.schema.json`、normal-form golden、および resource/observation construction test が型を含む identity を固定します。 |
| 3 | `Workspace_scan` は retained handle から内容を固定し、`Sidecar_snapshot` は bytes と ContentIdentity を保持します。`Workspace_graph` は終了時 inventory を再観測し、変化時は試行全体を一回だけ再実行します。 | mutation retry、stable read、graph query、および Extension Origin 再観測 test が、異なる試行の値を混在させないことを検査します。 |
| 4 | `Workspace_inspect` は、対応 Interpreter がない場合と Interpreter Failure の場合を含め、各固定済み Observation に Whole Region を追加します。 | Observation、unsupported observation、および Extension interpretation failure test が Whole Region と Coverage を確認します。 |
| 5 | `Region_id` は ObservationId を scope に含みます。部分 `Region` は exact InterpreterIdentity を値として保持し、`Region` と Extension result decoder は owning Observation と ObservationIdentity の一致を要求します。 | `region.schema.json` の Whole/partial 条件と semantic/runtime result-validation test が identity の暗黙補完および別 Observation の Region を拒否します。 |
| 6 | `Region_address` は Whole address で Interpreter を禁止し、すべての部分 address で exact InterpreterIdentity を必須にします。`Region_address_resolver` は InterpreterIdentity、ObservationIdentity、および Selector を一つの解決入力として扱います。 | command-result/Sidecar schema、constructor test、snapshot golden、および cross-interpreter resolve test が条件付き必須と exact dispatch を固定します。 |
| 7 | `Region_extent_relation` が五値、反転、および built-in extent 代数を実装し、`Region_extent_dispatcher` が Extension Interpreter の method へ exact dispatch します。 | semantic algebra test と `monika.classifyRegionExtents` runtime/conformance test が五値以外を拒否します。 |
| 8 | `Annotation` と `Reference` は SourceLocation や保存 encoding を持ちません。 | annotation/reference schema と Sidecar/inline golden が同じ意味値を異なる occurrence として表します。 |
| 9 | `Annotation_occurrence`、`Reference_definition_occurrence`、および `Reference_use` は相互に代用できない型と collection です。 | 個別 schema、repeated-reference test、および command-result golden が定義と使用箇所を分離します。 |
| 10 | `Workspace_scan` は予約済み Sidecar を primary Resource より前に分類し、`Sidecar_snapshot` として metadata plane に渡します。 | scan/check golden と metadata read/decode failure test が primary coverage と metadata coverage を分離します。 |
| 11 | `Sidecar_v2` は root の `scope.origin` を必須とし、filename から対象を推測しません。 | `sidecar-v2.schema.json` と strict Sidecar decode test が scope の欠落や未知 field を拒否します。 |
| 12 | `Annotation_index` と `Reference_index` は scoped ID ごとに全 occurrence を保持し、値が異なる場合は `Conflict` にします。Conflict と Diagnostic はその scoped ID に局所化され、無関係な一貫した値の操作を中止しません。 | conflict construction、ownership conflict、inspect/check golden、および unrelated source diagnostic を含む resolve golden が、divergent value を優先順位で隠すことと全 index を一括して失敗させることの両方を拒否します。 |
| 13 | `Source_location.In_sidecar` が `Authored` と `Derived` を保持し、`Sidecar_edit` と Deriver は Derived だけを再生成します。 | Sidecar schema、authored-byte preservation、および derive/apply/idempotency test が編集所有権を固定します。 |
| 14 | `DeriveRequest` は一つの `AnnotationOccurrence` または `ReferenceDefinitionOccurrence` を閉じた直和型で保持し、`Deriver_dispatcher` はその明示 occurrence から Patch を返します。Origin 全体の暗黙選択や、推測値を occurrence にする Infer fallback はありません。 | derive request/patch schema、単一 occurrence・重複拒否・無関係な derived record 保存 test、および derive golden が同じ入力から同じ patch を生成します。 |
| 15 | `Proposed_patch` が Create/Edit と前後 identity を表し、`Filesystem_apply` だけが handle-relative、atomic な publication を行います。 | patch schema、workspace transition golden、conflict、fault injection、および再適用 test が書き込み境界を検査します。 |
| 16 | `Registry_snapshot` は一回 decode した不変リストであり、操作全体へ同じ値を渡します。重複 capability identity は constructor が拒否します。 | registry schema version 2、registry construction test、および registry-backed CLI golden が snapshot 外の再探索を行わないことを固定します。 |
| 17 | Resource Observer、Interpreter、Region extent、二つの Extractor、Auditor、および Deriver は個別 dispatcher を持ちます。 | capability schema、capabilities golden、加算 Extractor/Auditor test、および全 role の conformance matrix が候補数と合成規則を検査します。 |
| 18 | `Workspace_resolve` と `Workspace_graph` は同じ `Region_address_resolver` を使用します。`resolve` は正規化済み RegionAddress の直接入力と、source Observation 内の Reference の両方を受け付けます。Reference の source と target は別々に観測し、target の exact InterpreterIdentity を新しい checked session へ渡します。すべての成功結果は target Observation と Region を含み、有限列挙にない解決済み Region も graph に追加します。 | standalone RegionAddress schema、resolve output semantic contract、direct/reference resolve golden、直接解決 test、selected-Region materialization test、および cross-interpreter resolve test が source session の隠れた状態、Region payload の欠落、および Interpretation 列挙への依存を拒否します。 |
| 19 | `Extension_runtime` は host-owned byte/structured input だけを protocol で渡します。`Extension_authority` と `Extension_sandbox` は通常 role と Resource Observer の権限を分離し、sandbox なしの起動を拒否します。 | 双方向 stream、sandbox probe、Resource Observer authority、Sidecar-scope observation、および unsupported-platform test が所有権境界を検査します。 |
| 20 | operation ごとの semantic result と `Extension_failure` が code、message、および data を保持し、`Command_boundary` が予期しない例外を internal failure に変換します。 | diagnostic/command-result schema、Failure fixture、timeout、I/O failure、および malformed-response test が空結果への変換を拒否します。 |
| 21 | `Coverage` は primary、observation、interpretation、および metadata の件数と完全性を保持し、graph/query が Diagnostic と同時に返します。 | coverage schema、related-result schema、および完全・不完全・失敗 golden が、空の edge collection と完全性を別々に表します。 |
| 22 | typed index と graph snapshot は ObservationIdentity、Sidecar ContentIdentity、および capability identity から毎回純粋に再構築します。意味に影響する可変 cache はありません。 | stable graph retry test と同一入力の golden comparison が、cache の有無で観測結果が変わらない境界を固定します。 |
| 23 | `schemas/`、`protocol/`、`golden/`、`spec/` が参照実装から独立した仕様層です。 | JSON/semantic contract、golden、workspace transition、idempotency、Sugar unit/runtime、および Bitter safe-integer/UTF-8 parity test を CI の全対象 OS で実行します。 |

## 追加の操作境界

- Sidecar scope の対象を観測できない場合も、decode 済み occurrence を index から削除しません。
  対象 Resource の失敗は別の Diagnostic と Coverage に記録します。
- Sidecar scope、Reference target、Annotation の RegionAddress、および direct use が要求する
  Origin を一つの集合として Coverage に数えます。未観測の workspace Origin は Failure、利用可能な
  Observer がないその他の Origin は unsupported とし、Extension Origin は新しい Observation が
  なくなるまで exact Resource Observer で固定点観測します。
- Extractor は Interpretation を任意入力として受け取ります。Interpreter が unsupported または
  Failure でも、Observation に適用可能な Extractor を独立して実行します。
- Relation の source と target は Region endpoint だけです。Reference-valued Annotation は、最終
  ReferenceIndex の consistent target を RegionAddress に解決できた場合だけ Relation へ射影し、
  Reference ID 自体を endpoint として残しません。未定義の Reference は occurrence を保持したまま
  `unresolved-ref` として診断します。
- Graph 構築は、consistent Reference、Annotation の RegionRef、および direct ReferenceUse の
  RegionAddress を重複なく exact resolve します。`interpretObservation` の成功や有限列挙とは独立して
  `resolveRegion` の endpoint status を保持し、成功した非列挙 Region を region query に利用します。
- `read`、`inspect`、`resolve`、`related`、`check`、および `derive` は、必要な箇所で同じ
  RegistrySnapshot、authority、および role-specific dispatcher を使用します。
- `monika extension test --executable` は initialization だけでなく、選択 role が宣言する全 method、
  typed Failure、process 終了、および sandbox setup を検査します。

## Platform 境界

macOS の Extension process は `sandbox-exec`、Linux は bubblewrap で隔離します。通常 role は
network と workspace を継承せず、read-only launch path、protocol channel、および bounded scratch
だけを受け取ります。Resource Observer の read/network authority は別 variant です。Windows は
現在 Extension process を実行せず `sandbox-setup-failed` を返します。どの platform でも
unsandboxed fallback はありません。Windows でも静的 manifest、registry、schema、および
Extension process を起動しない capability 列挙を検査します。

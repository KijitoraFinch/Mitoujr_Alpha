# Extension protocol の現状

実行可能な契約は、次のとおりです。

1. `monika extension test --manifest <file>` は、process を起動せず静的 manifest を検証します。
2. `--executable` を追加すると、fail-closed sandbox 内で `monika.initializeSession` の照合と
   capability が宣言するすべての method を検査します。
3. `monika inspect` に `--extension-manifest` と `--extension-executable` を追加すると、
   一時的な interpreter extension を起動して `monika.interpretObservation` を呼びます。
4. `monika read` は `inspect` と同じ一時 Extension または RegistrySnapshot から、固定済み
   Observation と明示情報を Agent 向け text として返します。
5. `--extension-registry` を指定すると、source と target の Interpreter を exact
   name/version で独立に dispatch して `monika.resolveRegion` を呼びます。
6. `monika related` は registry 内の複数 Interpreter で workspace graph を構築します。
7. Region 単位の `related` は `monika.classifyRegionExtents` で領域関係を判定します。
8. registry 内の適用可能な Reference Extractor をすべて独立に起動し、
   `monika.extractReferences` の定義 occurrence と ReferenceUse を加算します。
9. 適用可能な Annotation Extractor をすべて独立に起動し、
   `monika.extractAnnotations` の occurrence を加算します。
10. Extension Origin は exact Resource Observer の `monika.observeResource` で固定します。
11. `check` は `monika.audit`、`derive` は `monika.derive` に、同じ固定済み
    `WorkspaceGraphSnapshot` を渡します。

protocol version 1 の capability は、exact `acceptedObservationTypes`、
`applicability.pathGlobs`、`selectorSchemas`、および非空の `resultSchemas` を宣言します。
各 role は独立した dispatcher、request、成功 result、および Failure 契約を持ちます。
Extractor request の `interpretation` は任意です。Interpreter が選択できない Observation にも
適用可能な Extractor を実行し、`interpretation` を JSON `null` ではなく field 省略で表します。
その場合、ReferenceUse の source は `whole-observation` を使用できます。入力として渡されて
いない concrete Region ID を含む extraction は `invalid-result` として棄却されます。

通信形式、上限時間、process の終了条件、および JSON の制約は
[`protocol/extension-protocol.md`](../protocol/extension-protocol.md) に定めます。外部
extension の作成手順は [`extension-development.md`](extension-development.md) に記載
します。設計判断の理由と未実装の境界は
[`extension-runtime-design.md`](extension-runtime-design.md) に記載します。

`Origin`、`Observation`、`Selector`、および `Region` の意味は
[`resource-observation-model.md`](resource-observation-model.md) に定めていますが、
byte-backed Observation の内容は、host が request に続く bounded notification で
byte stream として渡します。構造化 Observation は schema identity と正規化済み JSON
value を渡します。Resource Observer が生成した byte 列は逆方向の bounded stream で host が
固定します。Interpreter などへの Observation content の所在として host filesystem の絶対 path、
再取得用 URI、または host resource token は渡しません。意味値内の宣言的な Origin は所在情報と
区別します。Resource Observer は Extension Origin と明示 authority を
別の入力境界で受け取ります。

Extension が返した失敗は、別の interpretation や region へ置き換えません。
すべての Extension diagnostic は、
`extensionFailure` に operation、extension 固有の code、および任意の data を
保持します。transport または JSON-RPC の失敗も同じ診断境界へ変換され、usage failure
と混同しません。

`related` は `CommandResult` ではなく version 7 の `RelatedResult` を返しますが、同じ
Diagnostic 形式を再利用します。安定した部分 graph を構築できた場合の capability failure は
`status: "incomplete"`、graph 自体を構築できなかった場合は `status: "failed"` とし、
いずれも Extension の code と data を結果から失いません。

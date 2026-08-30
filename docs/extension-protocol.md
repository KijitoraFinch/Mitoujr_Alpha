# Extension protocol の現状

実行可能な契約は、次の七つです。

1. `monika extension test --manifest <file>` は静的 manifest を検証します。
2. `--executable` を追加すると、外部プロセスを起動して `monika.initializeSession` を呼び、
   process が返した capability と静的 manifest を照合します。
3. `monika inspect` に `--extension-manifest` と `--extension-executable` を追加すると、
   一時的な interpreter extension を起動して `monika.interpretObservation` を呼びます。
4. `--extension-registry` を指定すると、source と target の Interpreter を exact
   name/version で独立に dispatch して `monika.resolveRegion` を呼びます。
5. `monika related` は registry 内の複数 Interpreter で workspace graph を構築します。
6. Region 単位の `related` は `monika.classifyRegionExtents` で領域関係を判定します。
7. registry 内の適用可能な Reference Extractor をすべて独立に起動し、
   `monika.extractReferences` の定義と use occurrence を加算します。

protocol version 1 で通常コマンドから実行する capability は `interpreter` と
`reference-extractor` です。ほかの既知の capability identity も manifest と初期化応答で
検査できますが、runtime method が未定義であるため通常コマンドは呼び出しません。
`capability.schemas` は、現在使用する `selector` だけを受理します。

通信形式、上限時間、process の終了条件、および JSON の制約は
[`protocol/extension-protocol.md`](../protocol/extension-protocol.md) に定めます。外部
extension の作成手順は [`extension-development.md`](extension-development.md) に記載
します。設計判断の理由と未実装の境界は
[`extension-runtime-design.md`](extension-runtime-design.md) に記載します。

`Origin`、`Observation`、`Selector`、および `Region` の意味は
[`resource-observation-model.md`](resource-observation-model.md) に定めていますが、
Observation の内容は、host が request に続く bounded notification で byte stream として
渡します。Extension へ filesystem path、URI、または host resource token は渡しません。

Extension が返した失敗は、別の interpretation や region へ置き換えません。
`extension test`、`inspect`、`resolve`、および `related` の Extension diagnostic は、
`extensionFailure` に operation、extension 固有の code、および任意の data を
保持します。transport または JSON-RPC の失敗も同じ診断境界へ変換され、usage failure
と混同しません。

`related` は `CommandResult` ではなく version 4 の `RelatedResult` を返しますが、同じ
diagnostic 形式を再利用します。session の起動または初期化に失敗した場合は
`status: "failed"`、各 observation の解釈に失敗した場合は `status: "incomplete"` とし、
いずれも Extension の code と data を結果から失いません。

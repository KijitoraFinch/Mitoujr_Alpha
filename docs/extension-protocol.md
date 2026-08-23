# Extension protocol の現状

実行可能な契約は、次の四つです。

1. `monika extension test --manifest <file>` は静的 manifest を検証します。
2. `--executable` を追加すると、外部プロセスを起動して `monika.initializeSession` を呼び、
   process が返した capability と静的 manifest を照合します。
3. `monika inspect` に `--extension-manifest` と `--extension-executable` を追加すると、
   一時的な interpreter extension を起動して `monika.interpretObservation` を呼びます。
4. 同じ option を `monika resolve` に追加すると、一つの checked session で source の
   `monika.interpretObservation` と target の `monika.resolveRegion` を順に呼びます。

通信形式、上限時間、process の終了条件、および JSON の制約は
[`protocol/extension-protocol.md`](../protocol/extension-protocol.md) に定めます。外部
extension の作成手順は [`extension-development.md`](extension-development.md) に記載
します。設計判断の理由と未実装の境界は
[`extension-runtime-design.md`](extension-runtime-design.md) に記載します。

`Origin`、`Observation`、`Selector`、および `Region` の意味は
[`resource-observation-model.md`](resource-observation-model.md) に定めていますが、
Observation の内容は、`ContentIdentity` を持つ read-only byte resource として
`inlineText`、`inlineBase64`、または将来の `contentUri` で渡します。

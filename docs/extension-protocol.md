# Extension protocol の現状

実行可能な契約は、次の二つです。

1. `monika extension test --descriptor <file>` は静的 descriptor を検証します。
2. `--executable` を追加すると、外部プロセスを起動して `monika.describe` を呼び、
   process が返した capability と静的 descriptor を照合します。

通信形式、上限時間、process の終了条件、および JSON の制約は
[`protocol/extension-protocol.md`](../protocol/extension-protocol.md) に定めます。外部
extension の作成手順は [`extension-development.md`](extension-development.md) に記載
します。設計判断の理由と未実装の境界は
[`extension-runtime-design.md`](extension-runtime-design.md) に記載します。

現在の runtime は、`observe` と `resolveRegion` を通常コマンドから呼びません。
`Origin`、`Observation`、`Selector`、および `Region` の意味は
[`resource-observation-model.md`](resource-observation-model.md) に定めていますが、
Observation の内容を process 間で渡す形式はまだ定めていません。

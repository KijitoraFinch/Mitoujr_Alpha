# Extension protocol

## 適用範囲

protocol version `"1"` は、静的 descriptor と、外部プロセスを起動して
`monika.describe` を呼ぶ通信方式を定めます。`observe`、`resolveRegion`、
annotation の抽出、および patch の生成に使う値は、まだこの protocol version の
実行可能な契約に含めません。

この文書で extension process とは、Monika が直接起動し、標準入力と標準出力で
JSON-RPC message を交換する外部プロセスを指します。一つの message は、一つの
JSON-RPC request または response です。一回の session は、そのプロセスを起動して
から終了を確認するまでです。

## 静的 descriptor

descriptor は、`protocolVersion` と一つの `capability` を持つ閉じた JSON object
です。形式は [`extension-descriptor.schema.json`](../schemas/extension-descriptor.schema.json)
で定めます。descriptor には executable path、引数、条件分岐、pipeline などの
実行手順を書きません。

## プロセスの起動

現在の参照実装では、次の CLI で executable と引数を指定します。

```sh
monika extension test \
  --descriptor extension.json \
  --executable python3 \
  --argument extension.py
```

`--argument` は指定順に何度でも使用できます。Monika は shell を介さず、
executable と引数の配列を operating system の process API へ渡します。環境変数と
current working directory は Monika process から継承します。extension は current
working directory の特定の値に依存してはいけません。

descriptor と executable の永続的な登録方法は、この protocol version では定めません。

## Message の区切り

通信には JSON-RPC 2.0 を使用します。標準入力と標準出力は UTF-8 を使用し、一つの
JSON object を一行に書きます。各 message の末尾には LF を一つ書きます。JSON string
内の改行は JSON の escape sequence として書くため、物理的な改行にはなりません。

protocol version 1 では、Monika が request を一つ送り、対応する response を受け取って
から次の request を送ります。notification、batch request、および extension process
から Monika への request は使用しません。request ID は1から始まる正の整数です。

標準出力には protocol message 以外を書いてはいけません。診断用の log は標準エラー
出力へ書きます。

## JSON の制約

request と response には、次の制約を適用します。

- object の field name は重複できません。
- string と field name は正しい UTF-8 でなければなりません。
- number は `-9007199254740991` 以上 `9007199254740991` 以下の整数に限ります。
- 小数、`NaN`、および無限大は使用できません。
- array と object の入れ子は、最上位の値から128段までです。
- 定義されていない field は使用できません。
- optional field を使用しない場合は省略します。`null` で代用しません。

## `monika.describe`

Monika は process を起動した後、最初に次の request を送ります。

```json
{"jsonrpc":"2.0","id":1,"method":"monika.describe","params":{"protocolVersions":["1"],"maxMessageBytes":16777216}}
```

`protocolVersions` は Monika が使用できる version です。request の `maxMessageBytes` は、
Monika が送受信できる一つの message の最大 byte 数です。末尾の LF は数えません。

成功した extension は、使用する protocol version と capability を返します。

```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1","capability":{"type":"interpreter","name":"custom-markdown","version":"1"},"maxMessageBytes":16777216}}
```

result の `maxMessageBytes` は extension process が送受信できる最大 byte 数です。
`monika.describe` の完了後は、request と result に書かれた二つの上限のうち小さい値を
使用します。`monika.describe` 自体の response には、request で Monika が示した上限を
使用します。

返した descriptor は、CLI で指定した静的 descriptor と一致しなければなりません。
`mediaTypes` と `pathGlobs` の順序は比較に影響しません。それ以外の field は、値と
有無が一致しなければなりません。

request を処理できない場合は JSON-RPC error response を返します。

```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"method not found"}}
```

成功 response の `id` は request と一致しなければなりません。error response でも
通常は同じ ID を返します。request を JSON-RPC request として解釈できず、ID を取得
できなかった場合に限り、error response の `id` を `null` にできます。`result` と
`error` は同時に指定できません。正確な構造は
[`extension-runtime-describe.schema.json`](../schemas/extension-runtime-describe.schema.json)
で定めます。

extension process は、JSON-RPC 2.0 が定める `-32700`、`-32600`、`-32601`、`-32602`、
および `-32603` を、それぞれ parse error、invalid request、method not found、invalid
params、および internal error に使用します。提示された protocol version を一つも使用
できない場合は、code `-32001` と message `unsupported protocol version` を返します。

## 上限時間と終了

参照実装の既定値は次のとおりです。

| 対象 | 既定値 |
|---|---:|
| 一つの message | 16 MiB |
| request の書き込み開始から response の読了まで | 30秒 |
| 標準入力を閉じてから process が終了するまで | 1秒 |

Monika は session の最後に extension process の標準入力を閉じます。extension process は
EOF を受け取ったら処理を終え、終了 status `0` で終了しなければなりません。上限時間
までに終了しない場合、Monika は process を強制終了して回収します。

不正な response、上限超過、timeout、途中の EOF、書き込み失敗、および終了 status
`0` 以外は session の失敗です。失敗した session の process は再利用しません。

## 権限

この通信方式は extension process を sandbox 内で実行しません。process は Monika と
同じ operating system user の権限を継承します。「extension は workspace を直接変更
しない」という規則は protocol 上の要件ですが、現在の参照実装は operating system
の機能を使って書き込みを禁止していません。信頼できない executable を起動しては
いけません。

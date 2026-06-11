# Sugar / Bitter 境界案の比較

この文書は、Sugar、Bitter、仕様層、共通 runtime の境界についての議論を整理するためのメモです。現時点の結論ではなく、次の設計判断の材料として扱います。

## 背景

当初の方針では、OCaml の Sugar を参照実装、Rust の Bitter を高速実装とし、その間に独立した仕様層を置く想定だった。

ただし、次の懸念が出ている。

- モデル詳細を早く JSON Schema 側に切り出すと、設計探索が硬くなる。
- Schema を手動で同期すると、OCaml 型、JSON codec、JSON Schema、Rust 型、golden がずれやすい。
- 正規形 JSON が一致しても、ツールとしての副作用を含む挙動が一致するとは限らない。
- ファイル読み書き、atomic write、patch 適用、conflict 判定、snapshot 更新などを Sugar と Bitter の両方で実装すると、差分が生まれやすい。

そのため、単に「仕様層を独立させる」だけではなく、Sugar が所有する意味論、観測可能な正規形、Bitter の同等実装、共通化すべき workspace 操作を再整理する必要がある。

## 共通する前提

どの案でも、以下は維持する。

- Sugar は捨てる試作品ではなく、参照実装である。
- Bitter は Sugar と観測可能な振る舞いを合わせる高速実装である。
- 設定ファイルに手続きを書かない。
- helper や extension は直接書き込まず、patch または正規化済み操作を返す。
- `derive` と `infer` は分ける。
- golden test と診断コードは、実装間比較の基準として使う。

## 同値性の再定義

Bitter は高速化のための実装である。したがって、Sugar と Bitter の内部手順が厳密に同じである必要はない。

必要なのは、次である。

```text
同じ入力 workspace
+ 同じ command
+ 同じ policy
= 利用者から見て同じ結果
```

ここでの「同じ結果」は、内部 trace や中間表現の完全一致ではない。観測可能で、かつ互換性上意味がある結果の一致である。

一致させるべきもの:

- final workspace content
- created / modified / deleted file set
- command exit class
- diagnostics after normalization
- apply / derive / check の CommandResult after normalization
- snapshot cache after normalization
- golden に含める stdout JSON

完全一致を要求しないもの:

- 内部データ構造
- traversal order
- allocation strategy
- streaming するか batch 処理するか
- 中間 transaction の分割単位
- 非公開 trace
- 性能最適化のための cache layout。ただし外部から観測される snapshot 形式は一致させる。

つまり、Sugar は「同じ手順の oracle」ではなく、「同じ結果を定義する oracle」として扱う。

この再定義により、案 B と案 C の比較も変わる。案 C の common runtime は、Bitter の内部手順を Sugar と同じにするためではなく、workspace 破壊に直結する低レベル規則を共通化し、結果同値性を守りやすくするための選択肢である。

## 案 A: 独立仕様層を先に厚く固定する

### 概要

OCaml と Rust の間に、最初から比較的独立した仕様層を置く案。

```text
schemas/
diagnostics/
golden/
protocol/
tests/

Sugar -> 仕様層に従う
Bitter -> 同じ仕様層に従う
```

### 良い点

- 実装言語から独立した契約が早く見える。
- Rust 実装が Sugar の内部構造に引きずられにくい。
- 外部利用者や extension author に見せる面が早期に整理される。
- CI で schema、golden、診断コードを早く検査できる。

### 問題点

- モデル探索前に JSON Schema を固定しすぎる危険がある。
- Schema が一次設計になると、OCaml の型設計より JSON 表現が強くなりすぎる。
- Schema、OCaml 型、JSON codec、Rust 型の手動同期が重くなる。
- 正規形 JSON の一致だけでは、patch 適用など副作用を含む挙動の一致を保証できない。

### 向いている条件

- 外部 protocol が最初から強く要求される。
- モデルがかなり安定している。
- schema generation または drift detection の仕組みが最初からある。

## 案 B: Sugar が意味モデルを所有し、正規形を投影する

### 概要

Sugar の内部に意味モデルを置き、そこから観測可能な正規形へ写す案。

```text
Sugar semantic model
  -> normalize
    -> normal form
      -> JSON codec
      -> JSON Schema
      -> golden

Bitter
  -> same normal form JSON
```

この案では、外部表現を「転送用オブジェクト」ではなく、「観測可能な正規形」として扱う。

### 良い点

- OCaml の代数的データ型を使って、意味モデルを自由に探索できる。
- JSON Schema が一次設計にならない。
- 正規化関数を純粋関数として定義できる。
- `[@@deriving yojson, jsonschema, equal, compare]` のような PPX を正規形側に限定して使える。
- Rust は内部型を Sugar と同じにする必要がなく、正規形 JSON の一致を目標にできる。

### 問題点

- 正規形の設計を誤ると、内部モデルの重要な意味が観測不能になる。
- 正規形 JSON の一致だけでは、workspace 変更を含むツール挙動の一致が足りない。
- Schema generation の対象を内部モデルではなく正規形に限定する discipline が必要になる。

### `ppx_deriving_jsonschema` の位置づけ

`ppx_deriving_jsonschema` は、正規形から JSON Schema を生成する用途では有力である。

使う対象:

- CLI envelope の正規形
- diagnostic の正規形
- patch の正規形
- snapshot の正規形
- capability の正規形
- selector の正規形

避ける対象:

- Sugar の意味モデルそのもの
- 探索中の内部 ADT
- OCaml の variant encoding に外部 JSON を引きずらせる設計

## 案 C: 正規形から外れる部分を共通 workspace runtime に切り出す

### 概要

案 B を前提にしつつ、副作用を含む workspace 操作を Sugar と Bitter の二重実装にしない案。

```text
Sugar
  -> normal transaction
    -> common workspace runtime
      -> workspace state change
      -> normalized CommandResult

Bitter
  -> normal transaction
    -> same common workspace runtime
      -> same workspace state change
      -> same normalized CommandResult
```

ここでの目的は、effect を抽象化すること自体ではない。正規形だけでは表せない、または二重実装したくない部分を共通化することが主目的である。

### 共通 runtime に入れる候補

- path normalization
- file identity 計算
- file read
- precondition check
- text edit application
- atomic write
- create file
- delete file
- conflict 判定
- snapshot cache write
- normalized CommandResult

### 共通 runtime に入れない候補

- annotation の意味解釈
- selector の高レベルな意味論
- derive の判断
- check の診断判断
- policy 判断
- infer
- 任意 command execution
- workflow 的な条件分岐や loop

### 良い点

- ファイル操作、patch 適用、conflict 判定の差分が Sugar と Bitter 間で出にくい。
- 同じ normal transaction を入れたとき、同じ状態遷移になることを保証しやすい。
- Rust で runtime を作れば、最終配布物に組み込みやすい。
- Sugar は subprocess または JSON-RPC で runtime を呼べばよく、filesystem transaction の細部を持たずに済む。

### 問題点

- 共通 runtime 自体が新しい中核コンポーネントになる。
- 境界を誤ると、小さな workflow engine になりかねない。
- Sugar 単体で完結しないため、参照実装としての自律性が少し下がる。
- OCaml から Rust runtime を呼ぶ場合、テスト環境や bootstrap がやや複雑になる。

### 比較対象

この案では、実装一致の基準は正規形 JSON だけではない。

```text
initial workspace snapshot
+ normal transaction
+ common runtime semantics
= final workspace snapshot
+ normalized CommandResult
+ diagnostics
+ exit code
```

つまり、同じ初期状態と同じ正規形入力に対して、同じ観測可能な状態遷移を起こすことを基準にする。

## 案 D: Sugar にすべて入れ、Bitter は型と実装で追随する

### 概要

モデル化、正規化、patch 適用、副作用処理まで、いったん Sugar に厚く入れる案。Bitter は Sugar の振る舞いに合わせる。

```text
Sugar
  semantic model
  normalization
  check / derive / apply
  workspace operation
  golden oracle

Bitter
  same observable behavior
```

### 良い点

- 参照実装としての Sugar が完全に自律する。
- 設計探索が最も速い。
- 仕様発見の段階では、複数コンポーネントの同期を考えなくてよい。
- OCaml で全体の意味論を一度きれいに書ける。

### 問題点

- filesystem transaction、atomic write、patch 適用などを Bitter でも再実装する必要がある。
- 正規形の外側で二重実装差分が出やすい。
- 後から共通 runtime を切り出す場合、移行コストが高くなる可能性がある。
- Rust 側が追随すべき面が広くなりすぎる。

### 向いている条件

- まず仕様発見を最優先したい。
- runtime 境界の設計がまだ時期尚早である。
- 副作用を含む適用処理の範囲が当面かなり小さい。

## 比較表

| 観点 | 案 A: 仕様層先行 | 案 B: Sugar 正規形 | 案 C: 共通 runtime | 案 D: Sugar 全部 |
| --- | --- | --- | --- | --- |
| モデル探索の自由度 | 低め | 高い | 高い | 最も高い |
| Schema 手動同期リスク | 高い | 低め | 低め | 中程度 |
| 副作用挙動の一致 | 弱い | 弱い | 強い | Bitter 側が重い |
| Sugar の自律性 | 高い | 高い | 中程度 | 最も高い |
| Bitter 実装負荷 | 中程度 | 中程度 | 低め | 高い |
| 初期実装の単純さ | 中程度 | 高い | 低め | 高い |
| 後から配布物に載せやすいか | 中程度 | 中程度 | 高い | 中程度 |

## B か C に振る場合の嫌な失敗

ここでは、案 B と案 C のどちらに寄せるかを検討するために、起きそうな失敗を先に列挙する。

### 案 B の嫌な失敗: 正規形 JSON だけが一致している

案 B では、Sugar の意味モデルから正規形へ写し、Bitter も同じ正規形を出すことを重視する。

このとき起きうる嫌な失敗は、JSON と golden は一致しているのに、実際の tool としての挙動が違うことである。

例:

- 同じ `ProposedPatch` JSON を出しているが、改行コードの扱いが Sugar と Bitter で違う。
- 同じ edit range を出しているが、byte offset と Unicode scalar offset の扱いが違う。
- 同じ conflict 診断を出しているが、片方だけ一部ファイルを書き換えた後に失敗する。
- 同じ snapshot JSON を出しているが、cache file の書き込み順や破損時の扱いが違う。
- 同じ path を出しているが、symlink、case sensitivity、`..`、絶対 path の処理が違う。

この失敗は、特に `apply`、snapshot 更新、cache、atomic write で表面化しやすい。

### 案 B の嫌な失敗: 正規形が肥大化する

副作用の差分を正規形 JSON で吸収しようとすると、正規形が実行計画のように肥大化する可能性がある。

例:

- patch JSON に filesystem precondition、identity、write mode、newline policy、encoding policy、atomicity policy が増え続ける。
- snapshot 更新のために、正規形が cache layout まで含み始める。
- 正規形が「観測可能な値」ではなく「小さな命令列」になっていく。

この状態になると、案 B と言いながら実質的には runtime protocol を作っているのに、runtime 境界が明示されていない状態になる。

### 案 B の嫌な失敗: Bitter が外側で再実装地獄になる

Sugar と Bitter が同じ正規形を出せても、その後の適用処理をそれぞれが持つなら、Bitter は次のような細部を再実装することになる。

- text edit application
- conflict detection
- path normalization
- content identity
- atomic write
- partial failure recovery
- snapshot cache update

この部分は高速化の主戦場ではあるが、意味論としては面白くない。しかもバグると workspace を壊す。

### 案 B の嫌な失敗: Sugar の oracle 性が過大評価される

Sugar が出す正規形を oracle とみなしても、workspace の状態遷移まで oracle 化できていない場合がある。

その結果、テストが次のように甘くなる。

```text
Sugar output JSON == Bitter output JSON
```

しかし本当に必要なのは次である。

```text
same initial workspace
+ same operation
= same final workspace
+ same CommandResult
+ same exit behavior
```

案 B 単体では、後者を意識的に足さないと抜けやすい。

### 案 C の嫌な失敗: runtime が workflow engine になる

案 C では、正規形から外れる workspace 操作を共通 runtime に切り出す。

このとき最も嫌なのは、runtime がただの実行基盤ではなく、判断を持つ workflow engine になってしまうことである。

例:

- runtime が annotation の意味を知る。
- runtime が selector の fallback を決める。
- runtime が policy に応じて診断 severity を変える。
- runtime が条件分岐や loop を持つ。
- runtime が任意 command execution を実行する。

こうなると、「設定ファイルに手続きを書かない」という方針と同じ問題を、runtime protocol に移しただけになる。

### 案 C の嫌な失敗: Sugar の参照実装としての自律性が落ちる

runtime を Rust crate として共通化し、Sugar から subprocess や JSON-RPC で呼ぶ場合、Sugar 単体で参照実装として完結しにくくなる。

例:

- OCaml のテストを実行するだけなのに Rust runtime build が必要になる。
- runtime protocol の version mismatch で Sugar 側のテストが落ちる。
- Sugar のモデル探索中に、runtime 側の制約へ引っ張られる。
- 「OCaml で明快な参照実装を書く」という目的が薄まる。

これは bootstrap 初期には特に重い。

### 案 C の嫌な失敗: 境界が早すぎて設計が固まる

normal transaction を早く固定しすぎると、まだ分かっていない patch、selector、snapshot の設計が runtime protocol に固定される。

例:

- text edit だけを前提にしたため、後で structured edit を扱いにくくなる。
- file identity の定義を早く固定しすぎて、git blob、hash、mtime、etag の扱いを後から変えにくい。
- snapshot cache の layout を runtime に含めたため、cache 戦略を変えにくい。

案 C は共通化の効果が大きい一方、早すぎる抽象化の危険もある。

### 案 C の嫌な失敗: デバッグ境界が増える

Sugar、Bitter、runtime の三者構成になると、失敗したときに原因の切り分けが難しくなる。

例:

- Sugar が間違った transaction を出したのか。
- runtime が正しく解釈できなかったのか。
- Bitter が Sugar と違う transaction を出したのか。
- golden が transaction を検査していないのか。
- final workspace snapshot の正規化が間違っているのか。

この失敗を避けるには、runtime に渡した normal transaction、CommandResult、workspace before/after snapshot をすべて記録できる必要がある。

### 案 C の嫌な失敗: common runtime が portability bottleneck になる

共通 runtime を Rust で実装すると、最終的な配布には有利である。しかし、Sugar の開発環境では依存が増える。

例:

- OCaml だけで作業したい場面でも Rust toolchain が必要になる。
- runtime の build が CI のボトルネックになる。
- Windows、macOS、Linux の filesystem 差分を runtime が強く背負う。
- runtime のバイナリ protocol が extension protocol と混線する。

### B に振る場合に必要な対策

案 B に振るなら、正規形 JSON の一致だけに閉じない検証を最初から置く必要がある。

必要な対策:

- apply 系のテストでは、final workspace snapshot を golden に含める。
- text edit application は Sugar 内で純粋関数としてまず実装し、Bitter との差分を golden で捕まえる。
- path normalization、newline、encoding、offset の規則を早く固定する。
- 正規形が命令列化し始めたら、案 C へ寄せる判断基準を置く。

案 B で進む場合の危険信号:

- patch schema に filesystem 実行詳細が増え続ける。
- Bitter 側で apply 周りのバグが増える。
- golden が stdout JSON しか見ていない。
- 「同じ JSON だが workspace が違う」バグが出る。

### B から C への移行容易性

案 B から案 C への移行は、正規形の設計が実行境界を意識していれば比較的可能である。

移行しやすい条件:

- patch、CommandResult、workspace snapshot が正規形として既に分離されている。
- text edit application が純粋関数としてまとまっている。
- path normalization、content identity、newline policy が個別 module になっている。
- apply 系テストが final workspace snapshot を検査している。

移行しにくくなる条件:

- Sugar の apply 実装が selector、diagnostic、filesystem 操作を密結合している。
- patch schema が実行詳細を無秩序に抱え込んでいる。
- golden が command stdout しか見ていない。
- workspace before/after を記録する fixture 形式がない。

したがって、B に振る場合でも、後から C へ切り出せるように、`apply` 周辺を module 境界として明確にしておく必要がある。

### C に振る場合に必要な対策

案 C に振るなら、runtime の責務を狭く固定する必要がある。

必要な対策:

- runtime は annotation、selector、derive、check の意味を知らない。
- runtime は normal transaction を実行し、normalized CommandResult を返すだけにする。
- 条件分岐、loop、任意 command execution は入れない。
- runtime protocol の POC は `apply_text_edits` だけに限定する。
- Sugar 単体でも pure interpreter を持てるか検討する。

案 C で進む場合の危険信号:

- runtime に policy 判断が入り始める。
- runtime が selector 解決を知り始める。
- runtime protocol の versioning が Phase 1 から重くなる。
- Sugar のテストに Rust runtime build が必須になり、探索速度が落ちる。

### C から B への移行容易性

案 C から案 B へ戻す移行もありえる。共通 runtime の境界が早すぎた、または runtime protocol が設計探索を妨げた場合である。

戻しやすい条件:

- runtime protocol が小さく、`apply_text_edits` 程度に限定されている。
- runtime に annotation、selector、derive、check の意味論が入っていない。
- Sugar 側にも同じ transaction を解釈する pure interpreter がある。
- runtime の入出力が normal form として golden 化されている。

戻しにくくなる条件:

- runtime が snapshot cache layout や policy 判断まで持っている。
- Sugar の apply が runtime 呼び出しなしではテストできない。
- runtime protocol が extension protocol と混線している。
- workspace 操作以外の意味論が runtime に流出している。

したがって、C に振る場合でも、最初から runtime を唯一の実行器にしない。Sugar 側に純粋な小型 interpreter を残すか、少なくとも runtime 入出力を完全に記録できる形にする。

## テストで補完できる範囲

B と C の差は、テスト設計でもかなり補完できる。ただし、補完できるものとできないものを分ける必要がある。

### 補完しやすいもの

- 正規形 JSON の一致。
- diagnostics の code、severity、対象 artifact、range の一致。
- patch の構造の一致。
- apply 後の workspace content の一致。
- `derive -> apply -> derive` の空性。
- `apply` の二回目が不要な変更を出さないこと。
- fixture に対する final snapshot の一致。
- path normalization の table test。
- text edit application の property test。

### 補完しにくいもの

- 実 filesystem の atomicity。
- process crash 中の partial failure recovery。
- OS ごとの filesystem 差分。
- symlink、case sensitivity、permission error。
- 並行実行時の race。
- 大規模 workspace での性能上の shortcut が意味を変えるケース。

このため、B に振る場合でも、filesystem に近い部分は property test と integration test をかなり厚くする必要がある。C に振る場合は、この厚いテスト対象を common runtime 側へ寄せられる。

### 必要な test layer

B でも C でも、最低限ほしい test layer は次である。

```text
model unit test
  Sugar の意味モデルと normalize の検査。

normal-form golden test
  Sugar と Bitter の stdout JSON、diagnostics、patch、snapshot を比較する。

workspace transition golden test
  initial workspace と command から final workspace と CommandResult を比較する。

operation/property test
  text edit、path normalization、content identity、conflict detection を小さく検査する。

failure-mode integration test
  conflict、changed file、missing file、permission error、partial write を検査する。
```

案 B は、このうち operation/property test と failure-mode integration test を Sugar/Bitter 両方に対して行う必要がある。案 C は、その多くを common runtime に寄せられる。

## B と C の選択基準

現時点での分岐は、次の問いで判断するのがよい。

### B に寄せるべき場合

- まず Sugar の意味モデル探索を最優先したい。
- workspace 書き込みは当面小さく、純粋関数で十分検証できる。
- apply の実装差分は後から golden で捕まえられる見込みがある。
- runtime protocol を今固定するのは早いと感じる。

### C に寄せるべき場合

- apply、snapshot、cache、atomic write が早期から重要になる。
- workspace を壊す種類のバグを二重実装したくない。
- Sugar と Bitter の一致基準に、final workspace snapshot を最初から含めたい。
- 正規形 JSON がすでに実行計画に近づいている。

## 暫定判断

いま B と C のどちらかに振るなら、判断の焦点は次である。

```text
正規形から外れる workspace 操作を、テストで補完しながら Sugar と Bitter の二重実装として許容できるか。
```

許容できるなら案 B に寄せる。  
許容できない、または workspace 書き込み差分が早く問題になりそうなら案 C に寄せる。

ただし、案 C に振る場合でも、最初から大きな runtime を作らない。最初の POC は `normal patch -> apply text edits -> normalized CommandResult` に限定する。

## 現時点の判断

現時点では、案 B に振るのが妥当である。理由は、まだ selector、patch、snapshot、正規化規則の意味論を発見している段階であり、common runtime や normal transaction を早く固定すると設計探索が硬くなるからである。

```text
1. Sugar に意味モデルを置く。
2. 意味モデルから観測可能な正規形へ写す。
3. JSON Schema は正規形から生成する。
4. golden は正規形 JSON と workspace transition として持つ。
5. patch 適用や workspace 更新は、まず Sugar 内の module と純粋関数で実装する。
6. Bitter は内部手順ではなく、利用者可視の結果同値性に追随する。
```

ただし、案 C への移行可能性は残す。次の条件が出た場合は、common workspace runtime の POC を検討する。

```text
apply 周辺で Sugar / Bitter 差分が複数回出る
patch schema が filesystem 実行詳細を抱え始める
failure-mode test を両実装に重複して大量に書く必要がある
atomic write や partial failure recovery が早期に重要になる
正規形が実質的に runtime 命令列になり始める
```

## 次に確認すること

- `Normal_*` という命名でよいか。それとも `Canonical_*`、`Observed_*`、`Surface_*` など別名がよいか。
- JSON Schema generation を `ppx_deriving_jsonschema` で十分に制御できるか。
- workspace transition golden の最小形式をどうするか。
- Sugar 内の `Workspace_ops` をどこまで純粋関数として切り出すか。
- C へ移る判断基準を test failure や保守負荷としてどう記録するか。

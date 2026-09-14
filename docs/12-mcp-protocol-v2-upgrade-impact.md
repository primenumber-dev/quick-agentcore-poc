# MCPプロトコルバージョン v1(2025-11-25)→v2(2026-07-28)移行の影響調査

> この章で分かること
> 新規開発(Step1以降)でMCPプロトコルバージョン「2026-07-28」を採用する方針に対し、対応SDKへのバージョンアップが既存クライアント(旧バージョンのみ対応するMCPクライアント)との互換性にどう影響するか、本プロジェクトのAgentCore Runtime/ECSホスティングにどう影響するかを机上調査した。

作成日: 2026-09-02(2026-09-02追記: v2 SDKのGA時期を訂正、§6参照) | 検証方法: 公式ドキュメント・SDKソース・AWS公式ブログの机上調査(実装・実機検証は未実施)

> **訂正(2026-09-02同日)**: 本調査時点では「v2対応TypeScript SDKは現時点でベータ版」と結論づけていたが、その後の追加確認で**v2は仕様(2026-07-28)と同時に既に正式リリース(GA)済み**であることが判明した。「GAを待ってから移行」という本文中の推奨は前提が崩れている。詳細・訂正版の推奨は§6を参照。

---

## TL;DR

| # | 論点 | 結論 |
|---|---|---|
| 1 | 「2026-07-28」は実在するか | **実在する正式なMCP仕様のリビジョン**。[公式仕様サイト](https://modelcontextprotocol.io/specification/2026-07-28)・[公式ブログ](https://blog.modelcontextprotocol.io/posts/2026-07-28/)で確認済み。「プロトコル発表以来最大の改訂」と位置付けられている |
| 2 | 現状とのギャップ | 本リポジトリのSDK(`@modelcontextprotocol/sdk` v1.29.0)は`2025-11-25`が最新対応バージョンで、v2の1つ前。SDK側はv1系からv2系への**メジャーバージョンアップ**(パッケージ自体が`@modelcontextprotocol/server`等に分割される)が必要 |
| 3 | 【最重要】クライアントバージョンによらず使えるか | **SDK側は「両対応」をデフォルト方針としている**。新SDKの`createMcpHandler(factory)`は`legacy: 'stateless'`がデフォルトで、旧世代(`initialize`ハンドシェイクを使うクライアント)と新世代(`_meta`で自己申告するクライアント)を**同一エンドポイントで同時に処理**する設計。ただし「バージョンを上げるだけで自動的にこうなる」わけではなく、新APIサーフェス(`createMcpHandler`)への移行が前提 |
| 4 | v2の主な変更点 | `initialize`/`initialized`ハンドシェイクの廃止、**`Mcp-Session-Id`ヘッダーがプロトコルのコア仕様から除外**(SEP-2567)、Multi Round-Trip Requests(MRTR)によるelicitation/sampling置き換え、Tasksが実験的機能から正式Extensionへ降格、DCRの位置づけ後退(Client ID Metadata Documentsを推奨) |
| 5 | AgentCore Runtimeへの影響 | AWS側は既に追随済み。[AgentCore RuntimeのMCPプロトコル契約文書](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp-protocol-contract.html)は2026-07-28に明示的に言及しており、AgentCore Gatewayも`supportedVersions`に含めている。**ただしRuntimeが付与する`Mcp-Session-Id`(microVMスティッキー用、[08番§3](./08-weekly-verification-plan.md)で扱った仕組み)はMCP仕様のバージョンとは独立したRuntime層の挙動**であり、v2でプロトコルコアからセッションIDが無くなっても、AgentCore側の要求は変わらない見込み |
| 6 | 今すぐ移行すべきか | **v2は2026-07-28に仕様と同時に既にGA済み**(本調査時点の「ベータ版」という認識は誤りだった、訂正済み)。移行自体はメジャーな書き換え(`McpServer`/`StreamableHTTPServerTransport`の手組み実装→`createMcpHandler`)を伴うため、GA待ちではなく**移行プロジェクトとしての計画着手が可能な段階**にある |

---

## 1. 「2026-07-28」は実在する仕様である

调査の結果、「2026-07-28」はユーザーが誤ってSDKのリリース日等と混同したものではなく、[modelcontextprotocol.io/specification/2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28)として公開されている**正式なMCP仕様のリビジョン**であることを確認した。[公式ブログ記事](https://blog.modelcontextprotocol.io/posts/2026-07-28/)では「プロトコル発足(2024年11月)以来、最大の改訂」と位置付けられている。1つ前の`2025-11-25`は2025年11月(プロトコル1周年)にリリースされたリビジョンで、本プロジェクトのSDKが対応している最新バージョンである。

実際にリポジトリにインストール済みのSDK(`server/node_modules/@modelcontextprotocol/sdk/dist/esm/types.js`)を直接確認したところ、次のようにハードコードされていた。

```js
LATEST_PROTOCOL_VERSION = '2025-11-25'
SUPPORTED_PROTOCOL_VERSIONS = ['2025-11-25','2025-06-18','2025-03-26','2024-11-05','2024-10-07']
```

つまり現状のSDK(`^1.29.0`)は、採用予定の`2026-07-28`のちょうど1つ手前のリビジョンまでしか対応していない。

## 2. バージョンネゴシエーションの仕組み — 「クライアントのバージョンによらず使えるか」への回答

### 2.1 現行(v1系SDK)の挙動

現行SDKの実装(`server/node_modules/@modelcontextprotocol/sdk/dist/esm/server/index.js`)を確認したところ、`initialize`リクエストで次のようにネゴシエーションしている。

```js
const requestedVersion = request.params.protocolVersion;
const protocolVersion = SUPPORTED_PROTOCOL_VERSIONS.includes(requestedVersion)
  ? requestedVersion
  : LATEST_PROTOCOL_VERSION;
```

クライアントが要求したバージョンが`SUPPORTED_PROTOCOL_VERSIONS`に含まれていればそれを、含まれていなければサーバー側の最新版を使う、という設計。**この仕組み自体は、v1系のマイナーバージョンアップ(例: 1.29.0→1.30.0)には既に対応しており、古いクライアントを壊さない**。

### 2.2 v2(2026-07-28)がもたらす変化

しかし`2026-07-28`は、ネゴシエーションの「対象となるリストを増やす」レベルの変更ではなく、**ハンドシェイク方式そのものを変える**改訂である。`initialize`/`initialized`という往復自体が廃止され、各リクエストが`_meta`で自身のプロトコルバージョン・ケーパビリティを自己申告する方式に変わる。これは配線レベルの破壊的変更であり、TypeScript SDK側の回答は**新しいv2 SDK**(`@modelcontextprotocol/server`/`@modelcontextprotocol/client`、2026-07-28に仕様と同時にGA済み)である。

[SDKの移行ガイド](https://ts.sdk.modelcontextprotocol.io/v2/migration/support-2026-07-28)によれば、推奨されるサーバーのエントリーポイント`createMcpHandler(factory)`は、デフォルトで`legacy: 'stateless'`が有効になっており、

- 旧世代(`initialize`ハンドシェイクを使うクライアント)は、リクエストごとにステートレスに振る舞う旧型サーバーのように内部でラップして処理
- 新世代(`_meta`で自己申告するクライアント)はそのまま新方式で処理

を**同一エンドポイントで同時にサポート**する設計になっている。SDK自身も「v1.xのクライアントは壊れない」ことを明言しており、v1系SDKもv2リリース後**最低6か月間**はバグ修正・セキュリティ修正を受け続けるとされている。

**結論**: 「クライアントのバージョンによらず使える」状態は達成可能で、それはv2 SDKの標準機能として用意されている。ただし、これは「SDKのバージョンを上げるだけ」で自動的に手に入るものではなく、**新しいAPIサーフェス(`createMcpHandler`)に実装を移行することが前提**である。

## 3. 本コードベースで必要になる変更

現状: `server/package.json`の`@modelcontextprotocol/sdk: ^1.29.0`。v2への移行はメジャーバージョンアップであり、パッチ/マイナー更新では済まない。

- パッケージ自体が分割される: `server/src/index.ts`が使っている`@modelcontextprotocol/sdk/server/mcp.js`・`.../server/streamableHttp.js`は無くなり、`@modelcontextprotocol/server`に置き換わる
- `index.ts`内の手組み実装(`new McpServer(...)`、`new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true })`、`server.connect(transport)`、`transport.handleRequest(req, res, req.body)`)は`createMcpHandler(factory)`への置き換えが必要
- スキーマ定義はStandard Schema経由でZodから分離される見込みだが、**Zod v4(本プロジェクトで既に使用中)はそのまま動作する**とされ、`registerQuickTools`配下の各ツール(`get_quote.ts`等)のスキーマ定義自体への影響は小さい見込み
- elicitation/sampling(本プロジェクトでは未使用)がMulti Round-Trip Requestsに置き換わるが、現状使っていないため直接の影響は無い
- v2 SDKは既にGA済みのため、仕様変動を追いかけ続けるコストは無い(ベータ期間中の変動リスクは解消済み)

## 4. 本プロジェクトの実装パターンへの影響

- 本サーバーは既に**ステートレス**(`sessionIdGenerator: undefined`)で稼働しており、これはv2が標準化しようとしている方向性そのものである。概念的な衝突は無い
- elicitation/sampling: 未使用のため、MRTRへの置き換えによる直接の影響は無い
- `enableJsonResponse: true`やAcceptヘッダーの扱いについて、v2で破壊的変更があるという情報は見つからなかった(ただし仕様の全項目を1対1で突き合わせた確認はできておらず、未確認事項として残る)

## 5. AgentCore Runtimeホスティングへのリスク

AWS側は既にv2に追随している。[AgentCore RuntimeのMCPプロトコル契約文書](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp-protocol-contract.html)には次のような記述がある(意訳)。

> MCPプロトコルバージョン2025-11-25以前では、elicitation/samplingにステートフルモードが必須。2026-07-28以降では、elicitation/samplingはMulti Round-Trip Requestsを使うため、ステートフルモードを必要としない

AgentCore Gateway(別コンポーネント)も`supportedVersions`に`2026-07-28`を含めている([AWS公式ブログ](https://aws.amazon.com/blogs/machine-learning/how-agentcore-gateway-supports-the-mcp-2026-07-28-spec/))。

**重要な点**: AgentCore Runtimeがプラットフォーム側で付与する`Mcp-Session-Id`([08番§3](./08-weekly-verification-plan.md)で扱ったmicroVMスティッキーのための仕組み)は、**MCP仕様のバージョンとは独立したRuntime層の挙動**である。AWS公式ドキュメントは「Runtimeは常にクライアントに`Mcp-Session-Id`ヘッダーを返す」「ステートレスサーバーはプラットフォームが付与するセッションIDを拒否せず受け入れなければならない」としており、これはステートレス/ステートフルいずれのモードでも変わらない。MCP仕様のコアから`Mcp-Session-Id`が除外されても、**AgentCore側の要求(このヘッダーを受け入れること)は変わらない見込み**である。

**結論: AgentCore Runtimeホスティングへのリスクは低い**。AgentCore側の対応も、TypeScript SDK v2自体も、共に準備が整っている。

## 6. 推奨(2026-09-02訂正版)

**訂正**: 本調査時点(2026-09-02)では「v2対応の公式TypeScript SDKは現時点でベータ版」としていたが、これは誤りだった。追加確認の結果、**v2は仕様(2026-07-28)のリリースと同時に既に正式リリース(GA)されている**ことが判明した(ベータはその前段階の話で、当時参照した情報が古かったか、ベータ期間の情報と混同していた)。パッケージは`@modelcontextprotocol/sdk`から`@modelcontextprotocol/server`・`@modelcontextprotocol/client`に分割されてGAしており、v1系は**v2リリース後最低6か月間**(2027年1月頃まで)バグ修正・セキュリティ修正を受け続ける設計。

これを踏まえた推奨:

- v2への移行は**非自明な書き換えプロジェクト**であり、既存のSDKバージョンアップ(マイナー/パッチ更新)とは性質が異なる。この点は変わらない
- **「GAを待つ」という判断根拠は無くなった**。既にGA済みのため、着手する場合は独立した移行プロジェクトとして計画できる段階にある。本プロジェクトの慣例(`terraform-playground-pattern4`のような検証用複製)に倣い、playgroundアカウントで先行検証してから本番相当コードに反映する進め方を推奨
- 「クライアントのバージョンによらず利用できるようにする」という目的自体は、v2 SDKの`createMcpHandler`のデフォルト挙動(`legacy: 'stateless'`)で標準サポートされる見込み。GA版で実際の挙動を実機確認することが次のステップになる
- Step1の着手時期・優先度次第では、最初からv2 SDKで新規実装するという選択肢も検討に値する(GA済みのため、ベータ追従リスクを負わずに済む)

Sources:
- [Beta SDKs for the 2026-07-28 MCP Spec Release Candidate](https://blog.modelcontextprotocol.io/posts/sdk-betas-2026-07-28/)(ベータ期間の告知。GA後の現在は`@modelcontextprotocol/server`/`@modelcontextprotocol/client`の安定版が公開されている)
- [MCP 2026-07-28 仕様](https://modelcontextprotocol.io/specification/2026-07-28)
- [公式ブログ: The 2026-07-28 Specification](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
- [2025-11-25 changelog](https://modelcontextprotocol.io/specification/2025-11-25/changelog)
- [TypeScript SDK v2 移行ガイド](https://ts.sdk.modelcontextprotocol.io/v2/migration/support-2026-07-28)
- [Google Cloud: Scaling AI agent infrastructure with the MCP stateless updates](https://developers.googleblog.com/scaling-ai-agent-infrastructure-with-the-mcp-stateless-updates/)
- [AgentCore Runtime MCP protocol contract](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-mcp-protocol-contract.html)
- [AWS公式ブログ: AgentCore Gateway supports MCP 2026-07-28](https://aws.amazon.com/blogs/machine-learning/how-agentcore-gateway-supports-the-mcp-2026-07-28-spec/)

---

## 7. 実機検証結果(2026-09-03、`feature/mcp-protocol-v2-spike`ブランチ)

机上調査(§1〜6)を受け、実際にv2 SDKへの載せ替えをローカル環境(LocalStackのDynamoDBスタブ)で実施し、動作確認まで行った。**本番`main`ブランチへの反映は行っていない**(スパイク止まりの方針、ユーザー確認済み)。

### 7.1 パッケージの実在確認

npmレジストリで実際に存在するか確認したところ、`@modelcontextprotocol/server@2.0.0`・`@modelcontextprotocol/client@2.0.0`・`@modelcontextprotocol/node@2.0.0`がいずれも`latest`タグでGA済みであることを確認した(§6の訂正内容と整合)。想定外だったのは**Express用の専用importパスが無い**点で、`package.json`の`exports`は`.`(コア)・`./stdio`・`./validators/*`のみ。型定義に埋め込まれたコメントによれば、Node系フレームワーク(Express/Fastify/plain `node:http`)は別パッケージ`@modelcontextprotocol/node`が提供する`toNodeHandler(handler)`でラップする設計になっている。

### 7.2 実際に必要だった変更

想定(§3)通り、変更は主に`server/src/index.ts`に集中した。

- `server/package.json`: `@modelcontextprotocol/sdk`を`@modelcontextprotocol/server`+`@modelcontextprotocol/node`に置換
- `server/src/index.ts`: `McpServer`インスタンス生成を`createMcpHandler(factory)`に、`StreamableHTTPServerTransport`の手組み(`server.connect`・`transport.handleRequest`)を`toNodeHandler(mcpHandler)`が返すNode用ハンドラの呼び出しに置き換え。GET/DELETE `/mcp`の固定応答スタブは**削除可能だった**——`createMcpHandler`のデフォルト(`legacy: "stateless"`)が同じ405応答を自動的に返すため
- **認可ゲート(`extractSub`+`resolveAuthorization`)はそのまま流用できた**。`McpServerFactory`が受け取る`authInfo`はOAuth標準の`AuthInfo`型(token/clientId/scopes必須)で本プロジェクトのCognito sub方式とは形が合わないため、無理に`authInfo`に載せず、Express側で`POST`メソッドのときだけ認可チェック→失敗時は`nodeHandler`を呼ばずに401/403を返す、という素通し構成にした。v1時代の「`resolveAuthorization`はゲートとして使うだけでツール登録には反映しない」という既存の設計をそのまま維持できている
- **ツール定義ファイル(6ツール)は無変更で動いた**。`server.registerTool(name, {...}, cb)`のプレーンオブジェクト(`ZodRawShape`)形式は、v2のAPI定義上`@deprecated`マーク付きだが、後方互換オーバーロードとして正式に残されている(`/** @deprecated Wrap with z.object({...}) instead. */`)。importパスの変更(`@modelcontextprotocol/sdk/server/mcp.js`→`@modelcontextprotocol/server`)のみで9ファイル(ツール6つ+コメントアウト中の2つ+index.ts)が無修正でコンパイル・実行できた

### 7.3 動作確認結果(ローカル、LocalStack DynamoDBスタブ)

`npm run dev`起動後、新規作成した`scripts/smoke_test_mcp_v2.sh`で以下をすべて確認(全項目PASS):

| # | 検証内容 | 結果 |
|---|---|---|
| 1 | `GET /health` | 200 |
| 2 | `POST /mcp`(認可ヘッダーなし) | 401(既存ゲートが機能) |
| 3 | `GET /mcp` | 405(v2ハンドラの自動応答、スタブ削除後も同じ挙動) |
| 4 | `DELETE /mcp` | 405(同上) |
| 5 | 旧世代クライアント相当の`initialize`ハンドシェイク(`protocolVersion: "2025-11-25"`) | 200、`legacyStatelessFallback`経由で正常応答 |
| 6 | 旧世代クライアント相当の`tools/list` | 200、6ツール全件を返却 |
| 7 | 新世代(v2)`_meta`エンベロープ形式の`tools/list`(`initialize`ハンドシェイクなし) | 200、6ツール全件を返却 |
| 8(スモークテスト外、手動確認) | `tools/call get_quote`に不正な引数(空配列・不正enum値)を渡す | `ZodRawShape`の入力バリデーションが実行時に正しく機能し、JSON-RPC結果内`isError: true`で人間可読なエラーメッセージを返却 |

**新世代クライアントの実際のリクエスト形**(机上調査時点では未確認だった具体的な必須ヘッダー・フィールドが判明):

- HTTPヘッダー`Mcp-Method`にJSON-RPCの`method`と同じ値を明示する必要がある(無いと`-32020`エラー: "the request headers and body disagree")
- リクエストボディの`params._meta`に`io.modelcontextprotocol/protocolVersion`と`io.modelcontextprotocol/clientCapabilities`の2キーが必須(無いと`-32602`エラーで不足キー名を列挙してくれる、エラーメッセージが親切)

### 7.4 結論・Step1着手判断への示唆

- **技術的には低リスクで移行可能**という§5〜6の見立ては実機でも裏付けられた。`createMcpHandler`への置き換えは局所的(`index.ts`とimport文のみ)で、ツール実装本体・Zodスキーマ・DynamoDB認可ロジックは無改修で動く
- **テストコードが皆無だった問題を副次的に解消できた**。今回作成した`scripts/smoke_test_mcp_v2.sh`は、legacy/modern両方のクライアント形・認可ゲート・GET/DELETE 405応答をカバーする回帰確認スクリプトとして今後も再利用できる(LocalStack起動が前提)
- **未検証で残る事項**: (a) AgentCore Runtime実機(playground)へのデプロイ・疎通確認(今回はローカルのみ)、(b) `initialize`を送らない新世代クライアントとClaude Code/Claude.aiのような実際のMCPクライアント実装が同じ`_meta`エンベロープ形を送ってくるかの確認(今回は仕様書の記述から手組みしたリクエストで代用)、(c) `enableJsonResponse: true`相当の設定(v1で明示していたJSON直接応答)がv2のデフォルト`responseMode: "auto"`でどう挙動するか(今回のテストはいずれも通常のJSON応答が返り、SSEへの昇格は発生しなかったが、意図的な差の確認はできていない)
- **本番`main`への反映判断**: 変更量が小さく後方互換オーバーロードで既存ツールが無改修で動く実績が取れたため、Step1の技術選定において「v2移行はハイリスクな書き換え」という当初の懸念は後退した。ただし(a)(b)の実機確認と、v1系SDKのセキュリティサポート期限(2027年1月頃)までの猶予を踏まえ、本番反映は独立したタスクとして計画してから着手することを推奨する

### 7.5 実機デプロイ・ECS側検証・機能テストスイート拡充(2026-09-08追記)

§7.4で「未検証」としていた(a)AgentCore Runtime実機デプロイと、当初スコープ外だったECS(パターン4)側の検証を実施した。あわせて、単発の`curl`確認に頼っていたこれまでの検証を、再現可能な自動テストスイート(`scripts/mcp_functional_tests.py`)として固定化した。

- **AgentCore Runtime実機デプロイ**: 検証専用Runtime`quickMcpPocV2SdkDemo`を新規作成し、v2スパイクイメージ(`v2-sdk-demo-1`タグ)をデプロイ。既存デモ用Runtime(v1 SDK)には一切触れていない
- **ECS実機デプロイ(新規)**: パターン4環境に検証専用サービス`quick-mcp-poc-v2-sdk-demo`(Fargate、amd64イメージ)を新規作成。既存のDCRデモ用サービス(`app`、v1 SDK)には一切触れず、独立したタスク定義・セキュリティグループ(自分のIPのみに制限した直接アクセス用)で稼働させている
- **機能テストスイート**: `initialize`ハンドシェイク・`tools/list`のスキーマ完全性・不正引数/未知ツール名/未知メソッドへのエラーハンドリング・`ping`・v1/v2プロトコルエンベロープの受理可否、の8項目を、v1-ECS/v2-ECS/v1-AgentCore/v2-AgentCoreの4環境すべてに対して自動実行。**32/32件合格**
- **新規発見(SDKの挙動差)**: 未知のツール名を`tools/call`した際、v1 SDKは`result.isError: true`(ツール実行結果としてのエラー)で返すのに対し、v2 SDKはトップレベルのJSON-RPCエラー(`code: -32602`、リクエスト自体の不正としてのエラー)で返す。クライアント側のエラーハンドリング実装によっては、この違いを吸収する対応が必要になる可能性がある
- これにより§7.4の「未検証で残る事項」(a)は解消。(b)(実際のMCPクライアント実装による新世代リクエストの検証)は今回も仕様書ベースの手組みリクエストによる代用のままで、引き続き未検証

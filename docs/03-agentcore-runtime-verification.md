# AgentCore Runtime 疎通検証ログ

> **この章で分かること**
> パターン3(AgentCore Runtime単体)を実際にデプロイし、MCPプロトコルで疎通するまでの一部始終。詰まった点とその原因・対応も含む、再現性のための実務ログ。構成図・比較は[01-architecture-comparison.md](./01-architecture-comparison.md)を参照。

検証日: 2026-08-14 〜 2026-08-17

## 目的

既存のquick-mcp-poc MCPサーバー(TypeScript実装、ECS/Fargate + API Gateway + Cognito構成)を、Amazon Bedrock AgentCore Runtimeにデプロイし、MCPプロトコルでの疎通を確認する。API Gateway/ECSパターンは今回のスコープ外。

## 検証環境

- **アカウント**: `systemN_playground`(883660531246、`ap-northeast-1`)
  - 本来の想定アカウント`professional_services_quick_poc`(620369151795)ではIAMロール作成権限(`iam:CreateRole`)が`AWSPowerUserAccess`ロールに無く、ブロックされたため、管理者権限を持つ別アカウントで検証を実施した。
  - このため、ECR・DynamoDB・IAMロールはすべて検証専用に新規作成しており、既存の本番寄りリソース(実クライアントデータを含む`quick-mcp-poc-users`テーブル等)には一切変更を加えていない。

## 実施内容

### 1. 環境構築(フェーズ0・1)
- Xcode Command Line Tools, Homebrew, AWS CLI, VSCode, GitHub CLI, Docker Desktop, Node.jsを導入
- AWS認証は IAM Identity Center(SSO)方式でプロファイル`quick-agentcore-poc`(本来のアカウント、読み取り用途)と`quick-agentcore-poc-playground`(検証実施用アカウント)の2つを設定
- Downloadsフォルダのzipから既存PoCコードを`~/projects/quick-agentcore-poc`に展開し、git初期化

### 2. 既存コード調査(フェーズ2)
- MCP SDKは公式`@modelcontextprotocol/sdk`、トランスポートは`StreamableHTTPServerTransport`(`sessionIdGenerator: undefined`)で**既にステートレス設計**であることを確認
- AgentCore要件との差分: ポート(3000→8000固定必須)、アーキテクチャ(arm64必須、既存はamd64前提)、認可フロー(DynamoDB参照、Cognito JWTのsubヘッダーに依存)
- 既存の認証フロー(API Gateway JWT Authorizerが検証済みsubを`x-cognito-sub`ヘッダーとして注入)とAgentCore Runtime(IAM/SigV4 or Custom JWT Authorizer)の認証モデルを比較し、日程優先で「IAM認証 + `requestHeaderAllowlist`によるカスタムヘッダー転送」を採用する方針とした

### 3. 改修・ローカル検証(フェーズ3)
- `server/src/index.ts`, `Dockerfile`のポートデフォルトを`3000`→`8000`に変更(アプリロジックは無変更)
- `pnpm-workspace.yaml`を追加(esbuildのビルドスクリプト承認を非対話環境で通すための対応)
- LocalStack DynamoDBでのローカル起動、Docker(`--platform linux/arm64`)ビルドの両方で`/mcp`への`tools/list`疎通、認可あり/なしの挙動(200/401/403)を確認

### 4. AWSデプロイ(フェーズ4)

作成したリソース(すべて`systemN_playground`アカウント、`ap-northeast-1`):

| リソース | 名前/ARN |
|---|---|
| IAM実行ロール | `arn:aws:iam::883660531246:role/quick-mcp-poc-agentcore-execution-role` |
| ECRリポジトリ | `883660531246.dkr.ecr.ap-northeast-1.amazonaws.com/quick-mcp-poc-agentcore-verification` |
| DynamoDBテーブル | `quick-mcp-poc-users`(検証用、テストユーザー1件のみ) |
| AgentCore Runtime | `arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocVerification-Aoo0d23yyj` |

AgentCore Runtime設定のポイント:
- `protocolConfiguration.serverProtocol = MCP`
- `requestHeaderConfiguration.requestHeaderAllowlist = ["x-cognito-sub"]`(疎通確認用に、検証済みユーザー識別子を転送)
- `networkConfiguration.networkMode = PUBLIC`

## 詰まった点・原因・対応

1. **開発機にHomebrew/AWS CLI/Docker等がほぼ何も入っていなかった**
   - Xcode Command Line Toolsから順に導入。sudoパスワードが必要な工程(Homebrewインストーラ、Docker cask)はTTYが無い実行環境のため失敗し、ユーザーに別ターミナルでの実行を依頼した。

2. **pnpm installが esbuild のビルドスクリプトで失敗**
   - 非対話環境のため`pnpm approve-builds`の対話プロンプトが完了できず、`pnpm-workspace.yaml`に`allowBuilds: { esbuild: true }`を追加して解決。Dockerfileの`deps`ステージにも`pnpm-workspace.yaml`のCOPYを追加。

3. **DynamoDBテーブルに実クライアントデータが存在していた**
   - 想定アカウントの`quick-mcp-poc-users`テーブルには実際のクライアントユーザー(quick.jpドメイン)41件が登録されていることが判明。書き込みは一切行わず、既存レコードの`sub`値を読み取り専用で参照する方針に変更(結果的に別アカウントでの検証となったため、このテーブル自体には未接触)。

4. **想定アカウントでIAMロール作成権限が無かった**
   - `AWSPowerUserAccess`では`iam:CreateRole`が拒否。組織のAWSアカウント一覧を確認し、ユーザーが管理者権限を持つ`systemN_playground`アカウントで検証する方針に切り替えた。

5. **AgentCore Runtimeへの初回リクエストが403**
   - 原因は`server/src/db.ts`の`TABLE_NAME`が`"quick-mcp-poc-users"`にハードコードされており、検証用に作成した`quick-mcp-poc-users-verification`テーブルと名前が一致していなかったため。テーブル名をコードに合わせて作り直すことで解決(コード変更なし)。

6. **`x-cognito-sub`のような任意のカスタムヘッダーをAWS CLIから直接付与できない**
   - `aws bedrock-agentcore invoke-agent-runtime`にはMCP関連の固定パラメータ(`--mcp-method`等)はあるが、汎用ヘッダー指定オプションが無い。boto3の`before-sign`イベントフックを使う小さなPythonスクリプトを作成して対応。

## 最終疎通結果

- `tools/list`(認証ヘッダーあり): **成功**。`get_quote`, `get_price_history`, `get_intraday_history`, `search_news`, `get_ranking`, `search_stocks`の6ツールを正しく取得
- `tools/list`(認証ヘッダーなし): **401**で正しく拒否(想定通り)
- ローカル/Docker(arm64)/AgentCore Runtimeの3環境すべてで同一の挙動を確認

## 汎用MCPクライアント疎通・レイテンシ測定(2026-08-21実施)

### 汎用MCPクライアントからの疎通(boto3/Claude Code/Claude.aiに依存しない検証)

`scripts/invoke_agentcore_mcp_jwt.py`を新規作成し、boto3/SigV4を使わず、Cognitoの認可コード+PKCEフローで取得したBearerトークンのみで`invocations`エンドポイントを直接HTTPS呼び出しするテストを実施した。

- ログイン(Cognito Hosted UIのログインフォームをHTTPで直接POST)→トークン交換→MCP呼び出しの一連の流れが**成功**
- `tools/list`: 6ツールを正しく取得(既存の検証と同一)
- `tools/call`(`get_quote`): MCPプロトコル層・JWT認証・DynamoDB認可チェックまで正常に到達し、`QUICK_API_USER / QUICK_API_PASS are not set`で失敗(playground環境に実APIシークレットを投入していないため。想定通りの結果で、認証・認可レイヤーの成功を裏付ける)
- **結論**: Claude Code/Claude.ai固有の実装に依存せず、MCP仕様(Streamable HTTP)とOAuth 2.0(Authorization Code + PKCE)に準拠する汎用クライアントであれば接続可能であることを実機で確認

### コールドスタート/レイテンシ測定

同スクリプトで、リクエスト間隔を変えて4回計測(アクセストークンは再利用、`--reuse-token`)。

| タイミング | レイテンシ(サーバー到達〜応答完了) |
|---|---|
| 直後(t=0) | 6.070秒 |
| 60秒後 | 5.948秒 |
| 5分後 | 5.874秒 |
| 16分後(`idleRuntimeSessionTimeout`=900秒を超過) | 6.089秒 |

`curl -w`でDNS/TCP/TLSハンドシェイクの内訳も取得したところ、`time_appconnect`(TLS完了)は0.1〜0.2秒程度で、`time_starttransfer`(最初の応答バイト)までが約6秒を占めていた。

**所見**: アイドル時間0秒〜16分(セッションタイムアウト超過後)まで、レイテンシに有意な差が見られなかった。一般的な「コンテナのコールドスタート」(アイドル後の初回リクエストのみ遅い)という現象は**今回の計測範囲では観測できなかった**。約6秒という値はほぼ全リクエストで一定であり、これはAWS側のコンテナ起動待ちというより、**MCPサーバー実装側(`server/src/index.ts`)がリクエストごとに新しいMCPサーバーインスタンス・トランスポートを生成している(`sessionIdGenerator: undefined`のステートレスStreamable HTTP)ことによる、リクエストごとの初期化コストの可能性が高い(推測、コード側の詳細プロファイリングは未実施)**。ECS(常時起動)との比較においては、「コールドスタートの有無」よりも「リクエストあたり一定の約6秒オーバーヘッドがあるかどうか」という観点で比較する方が実態に近い。

## 次のステップ(本タスクのスコープ外)

- 本番アカウント(`professional_services_quick_poc`)でのデプロイには、`docs/agentcore-iam/`配下のIAMポリシー(信頼ポリシー・権限ポリシー)をベースに、アカウントID(`883660531246`→`620369151795`)とECRリポジトリ名(`quick-mcp-poc-agentcore-verification`→`quick-mcp-poc`)を本番用に置き換えた上で、管理者にロール作成を依頼する必要がある
- Cognito JWTをAgentCore Runtimeの`Custom JWT Authorizer`で検証する構成(本番の信頼モデルに最も近い)への移行検討
- `QUICK_API_USER`/`QUICK_API_PASS`等の実APIシークレットをAgentCore Runtimeにどう渡すか(Secrets Manager連携等)の検討

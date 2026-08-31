# quick-mcp-poc: AgentCore Runtime移行検証 技術ドキュメント

来週水曜のクライアント報告に向けて実施した、Amazon Bedrock AgentCore Runtimeへのデプロイ検証、および既存のAPI Gateway + ECS構成との比較検証のまとめ。

## この技術文書の読み方

読者の目的別に、読む順番を変えることを想定している。

```mermaid
flowchart LR
    Q1{"何を知りたい?"}
    Q1 -->|"結論だけ知りたい"| A["このREADME<br/>(全体サマリー)"]
    Q1 -->|"どちらの構成を選ぶべきか"| B["01. アーキテクチャ比較"]
    Q1 -->|"コストで比較したい"| C["02. コストシミュレーション"]
    Q1 -->|"AgentCoreは実際に動くのか"| D["03. AgentCore検証ログ"]
    Q1 -->|"既存構成は生きているか"| E["04. ECS検証ログ"]
    Q1 -->|"金融機関向けに売るならセキュリティ/コンプライアンスは?"| F["05. セキュリティ・コンプライアンス比較検証"]
    Q1 -->|"実際にMCPクライアントから繋がるのか"| G["06. OAuth接続検証"]
    Q1 -->|"VPC/WAFに対応できるのか"| H["07. VPC/WAF/コスト追加検証"]
```

## ドキュメント一覧

| # | ドキュメント | 内容 | 主な読者 |
|---|---|---|---|
| 0 | [00-handoff.md](./00-handoff.md) | セッション引き継ぎメモ(現状・未着手事項・再開手順) | 作業を再開するエンジニア(人・AI問わず) |
| — | [RESUME_PROMPT.md](./RESUME_PROMPT.md) | 新規セッション開始時にコピペする再開プロンプト | セッションを再開する人 |
| 1 | [01-architecture-comparison.md](./01-architecture-comparison.md) | 構成図・Mermaidシーケンス図・プロコン比較 | 意思決定者、アーキテクト |
| 2 | [02-cost-simulation.md](./02-cost-simulation.md) | 月額コスト試算・損益分岐点 | 意思決定者、予算担当 |
| 3 | [03-agentcore-runtime-verification.md](./03-agentcore-runtime-verification.md) | パターン3(AgentCore Runtime)のデプロイ・疎通検証の詳細ログ | エンジニア(再現・引き継ぎ用) |
| 4 | [04-ecs-apigateway-verification.md](./04-ecs-apigateway-verification.md) | パターン4(API Gateway + ECS)の稼働確認ログ | エンジニア(再現・引き継ぎ用) |
| 5 | [05-security-compliance-verification.md](./05-security-compliance-verification.md) | 金融グレード有償リモートMCPサービスとしてのセキュリティ・コンプライアンス比較検証(マルチテナント分離・閉域網・監査ログ・コンプライアンス認定・FISC対応) | 意思決定者、顧客の情シス/監査部門への説明担当 |
| 6 | [06-agentcore-oauth-claude-code-verification.md](./06-agentcore-oauth-claude-code-verification.md) | ECS+API Gateway→AgentCore Runtime移行の詳細比較、Claude Code経由のOAuthリモートMCP接続検証(構成図・シーケンス図・認証フロー差分・接続手順・ハマりどころ) | エンジニア(再現・引き継ぎ用)、アーキテクト |
| 6c | [06-agentcore-oauth-claude-code-verification-client.md](./06-agentcore-oauth-claude-code-verification-client.md) | 06番のクライアント向け版(用語解説付き、対外報告用)。同内容のPDF版あり | クライアント(QUICK様) |
| 7 | [07-vpc-waf-cost-verification.md](./07-vpc-waf-cost-verification.md) | AgentCore RuntimeのVPCモード実機切り替え検証、WAF代替構成(CloudFront)検証、コスト再検討、DCR/CIMD机上調査、汎用MCPクライアント疎通・コールドスタート測定 | エンジニア(再現・引き継ぎ用)、アーキテクト |
| 7c | [07-vpc-waf-cost-verification-client.md](./07-vpc-waf-cost-verification-client.md) | 07番のクライアント向け版(用語解説付き、対外報告用) | クライアント(QUICK様) |
| — | [agentcore-iam/](./agentcore-iam/) | AgentCore Runtime実行ロール用のIAMポリシー一式 | 本番アカウント適用時の管理者 |
| — | [images/](./images/) | 構成図のPNGおよび生成元YAML([awsdac](https://github.com/awslabs/diagram-as-code)形式) | 図を再生成・改変したい人 |

## 全体サマリー

### やったこと

1. 検証環境(Homebrew, AWS CLI, Docker, Node.js等)をゼロから構築
2. 既存PoCコード(TypeScript製MCPサーバー)を調査し、AgentCore Runtimeの要件(ポート8000固定、`/mcp`パス、ステートレスStreamable HTTP、linux/arm64)との差分を洗い出し
3. 最小限の改修(ポート変更のみ)でAgentCore Runtimeにデプロイし、認可フロー(DynamoDB参照)を含めてMCPプロトコル(`tools/list`)の疎通を確認
4. 既存のAPI Gateway + ECS構成(本番相当、既に構築済み)の稼働状況を確認
5. 両パターンのアーキテクチャ比較(構成図・シーケンス図・プロコン)とコストシミュレーションを作成

### 主なはまりどころ

| # | 事象 | 原因 | 対応 |
|---|---|---|---|
| 1 | 開発機にツールがほぼ何も入っていなかった | 新規環境 | Xcode CLT→Homebrew→各種ツールの順に導入。sudo/GUI操作が必要な工程はユーザーに別ターミナルでの実行を依頼 |
| 2 | `pnpm install`がesbuildのビルドスクリプトで失敗 | 非対話環境で`pnpm approve-builds`の対話プロンプトが完了できない | `pnpm-workspace.yaml`に`allowBuilds`設定を追加(Dockerfileにも反映) |
| 3 | 想定アカウントでIAMロール作成が拒否された | `AWSPowerUserAccess`にIAM作成権限が無い | ユーザーが管理者権限を持つ別アカウント(`systemN_playground`)で検証を実施する方針に切り替え |
| 4 | DynamoDBに実クライアントデータ(41ユーザー)が存在していた | 既存本番相当環境のテーブルを調査中に発覚 | 書き込みは一切行わず、別アカウントに検証専用のテーブルを新規作成する方針に変更 |
| 5 | AgentCore Runtimeへの初回リクエストが403 | アプリコードのDynamoDBテーブル名がハードコードされており、検証用テーブル名と不一致 | テーブル名をコードに合わせて作成し直すことで解決(アプリコード変更なし) |
| 6 | `x-cognito-sub`のようなカスタムヘッダーをAWS CLIから直接付与できない | `invoke-agent-runtime`に汎用ヘッダー指定オプションが無い | boto3の`before-sign`イベントフックで対応する検証スクリプトを作成 |

### 認証まわりの設計判断

既存構成(パターン4)は API Gateway の JWT Authorizer が Cognito トークンを検証し、検証済みの`sub`を`x-cognito-sub`ヘッダーとしてアプリに渡す設計。AgentCore Runtime(パターン3)への移行にあたっては、スケジュール優先で「IAM認証 + カスタムヘッダーの自己申告」という簡略構成を採用して疎通確認のみを行った。本番展開時は Custom JWT Authorizer の導入(Cognitoとの統合)を検討する必要がある。詳細は[01-architecture-comparison.md](./01-architecture-comparison.md)の「本番採用時の注意」を参照。

### クライアント報告での使い分け

- **技術的な疎通性を示す**: [03-agentcore-runtime-verification.md](./03-agentcore-runtime-verification.md)
- **既存構成との比較・意思決定材料**: [01-architecture-comparison.md](./01-architecture-comparison.md) + [02-cost-simulation.md](./02-cost-simulation.md)
- **既存構成が生きていることの証跡**: [04-ecs-apigateway-verification.md](./04-ecs-apigateway-verification.md)
- **金融機関向け外販サービスとしてのセキュリティ・コンプライアンス説明**: [05-security-compliance-verification.md](./05-security-compliance-verification.md)
- **実際にMCPクライアントから繋がることを示す・移行の技術詳細**: [06-agentcore-oauth-claude-code-verification.md](./06-agentcore-oauth-claude-code-verification.md)(クライアント向け版: [06-agentcore-oauth-claude-code-verification-client.md](./06-agentcore-oauth-claude-code-verification-client.md))
- **VPC配置・WAF導入可否・コストの疑問に実機で答える**: [07-vpc-waf-cost-verification.md](./07-vpc-waf-cost-verification.md)(クライアント向け版: [07-vpc-waf-cost-verification-client.md](./07-vpc-waf-cost-verification-client.md))

## 図の再生成方法

構成図は[`awsdac`](https://github.com/awslabs/diagram-as-code)で生成している(`brew install awsdac`)。MCPサーバーとしてもClaude Codeに登録済み(`awsdac-mcp-server`、次回セッションから利用可能)。YAML仕様を編集して再生成する場合:

```bash
awsdac docs/images/pattern3-architecture.yaml -o docs/images/pattern3-architecture.png -f
awsdac docs/images/pattern4-architecture.yaml -o docs/images/pattern4-architecture.png -f
```

シーケンス図は[Mermaid](https://mermaid.js.org/)記法で各Markdownファイルに直接埋め込んでおり、GitHub上でそのまま描画される。編集時は[Mermaid Live Editor](https://mermaid.live/)でプレビューできる。

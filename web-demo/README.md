# quick-mcp-poc 疎通検証Webアプリ

playgroundアカウント(883660531246)にLambda Function URLとしてデプロイ済みの、クライアント向けデモアプリのソース。

- 関数名: `quick-mcp-poc-web-demo`
- Function URL(AuthType NONE): `https://ldqokcn33yxb2lspfudhahj2we0pgfqa.lambda-url.ap-northeast-1.on.aws/`
- 実行ロール: `quick-mcp-poc-web-demo-lambda-role`

このディレクトリは2026-09-06まで未コミットで、Lambda側にのみ存在していた(`aws lambda get-function`でzipを取得して復元)。以後はここが正となる。

## 機能

1. **疎通確認(OAuth PKCE)**: Cognitoでログインし、AgentCore Runtime(CloudFront+WAF経由)へ`tools/list`・`tools/call`を送る、既存の疎通検証機能
2. **応答時間デモ**([16-internal-weekly-verification-report-week3.md §1](../docs/16-internal-weekly-verification-report-week3.md)): セッションID再利用の有無で応答時間がどう変わるかを、ログイン不要のボタン1つで実測・左右比較表示
3. **DCRデモ**([15-internal-ecs-production-readiness-gaps.md §1](../docs/15-internal-ecs-production-readiness-gaps.md)): pattern4環境で自己登録→未承認403→承認→200→失効→403の一連の流れを実演。実行後にテスト用リソースを自動クリーンアップ
4. **WAFデモ**([15-internal-ecs-production-readiness-gaps.md §4](../docs/15-internal-ecs-production-readiness-gaps.md)): 正常リクエスト・XSSパターン・SQLiパターンをCloudFront+WAFv2経由で送り、通過/遮断を実測
5. **MCPプロトコルv2 SDKデモ**([12-internal-mcp-protocol-v2-upgrade-impact.md §7](../docs/12-internal-mcp-protocol-v2-upgrade-impact.md)): 現行デプロイ(v1 SDK)と`feature/mcp-protocol-v2-spike`ブランチのイメージを動かす専用Runtime(v2 SDK)の両方に、従来形式(initializeハンドシェイクを使う旧世代クライアント相当)・新形式(_metaエンベロープを使う新世代クライアント相当)のリクエストを送り、v1は新形式を拒否し、v2は両方に対応することを実測比較

## デプロイに必要な環境変数

| 変数名 | 値の入手方法 |
|---|---|
| `CLIENT_ID` | `quick-mcp-poc-web-demo`のCognito App Client ID(既存、`54cjhrb2bmba52upo8tfem4jlq`) |
| `M2M_CLIENT_ID` | `quick-mcp-poc-m2m-test`のCognito App Client ID(既存、`7gtknlcn9imrhihetq3aauojaj`) |
| `M2M_CLIENT_SECRET` | `aws cognito-idp describe-user-pool-client --user-pool-id ap-northeast-1_WSvFtGhlV --client-id 7gtknlcn9imrhihetq3aauojaj --profile quick-agentcore-poc-playground`で取得(git管理外、デプロイ時に都度取得すること) |

## SDKデモが依存するAgentCore Runtime

| Runtime | 用途 | イメージ |
|---|---|---|
| `quickMcpPocLatencyLab-uC4Wd7EOWj`(応答時間デモと共用) | v1 SDK側("現行サーバー") | `quick-mcp-poc-agentcore-verification:latency-lab-1` |
| `quickMcpPocV2SdkDemo-lxkNuS7moU` | v2 SDK側("v2アップデート後") | `quick-mcp-poc-agentcore-verification:v2-sdk-demo-1`(`feature/mcp-protocol-v2-spike`ブランチの`server/`をビルド) |

v2側イメージの再ビルドが必要な場合:

```bash
git checkout feature/mcp-protocol-v2-spike
cd server && pnpm install
docker buildx build --platform linux/arm64 \
  -t 883660531246.dkr.ecr.ap-northeast-1.amazonaws.com/quick-mcp-poc-agentcore-verification:v2-sdk-demo-1 \
  --push .
# Runtimeは自動的に最新イメージを使わないため、update-agent-runtimeで再デプロイが必要
```

## 必要なIAM権限(実行ロールへのインラインポリシー`dcr-demo-permissions`)

- `dynamodb:PutItem/UpdateItem/DeleteItem/GetItem` on `quick-mcp-poc-users`テーブル(DCRデモの承認・失効・クリーンアップ)
- `cognito-idp:DeleteUserPoolClient` on pattern4のユーザープール(`ap-northeast-1_XrU8FcC1w`、DCRデモのクリーンアップ)

Node.js 20.x/22.xのAWS管理ランタイムにはAWS SDK v3(`@aws-sdk/*`)がプリインストールされているため、`node_modules`を含める必要はない。

## デプロイ手順

```bash
cd web-demo
zip -j /tmp/code.zip index.mjs
aws lambda update-function-code \
  --function-name quick-mcp-poc-web-demo \
  --zip-file fileb:///tmp/code.zip \
  --profile quick-agentcore-poc-playground --region ap-northeast-1
```

タイムアウトは30秒に設定済み(応答時間デモが約10秒、DCRデモが約15秒かかるため)。

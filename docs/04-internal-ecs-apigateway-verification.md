# パターン4(API Gateway + ECS)稼働確認ログ

> **この章で分かること**
> パターン4(API Gateway + ECS)が既存本番相当アカウントで実際に稼働していることの確認記録。実クライアントデータへの影響を避けるための判断も記載する。構成図・比較は[01-internal-architecture-comparison.md](./01-internal-architecture-comparison.md)を参照。

検証日: 2026-08-17

## 背景

「MCP基盤 アーキテクチャ概略」で整理された4つの実装パターンのうち、パターン4(API Gateway → ECS、自前構成)は既存PoCの延長にあたる構成。本タスクでは新規デプロイは行わず、`professional_services_quick_poc`アカウント(620369151795、`ap-northeast-1`)に**既に構築済み**であることを確認した上で、稼働状況を検証した。

実クライアントデータ(Cognitoユーザー、DynamoDBの実ユーザー41件)を含む共有本番環境であるため、**新規Cognitoテストユーザーの作成や既存データへの書き込みは行わず、インフラの稼働確認のみ**を実施した(実施方針はユーザーと合意済み)。

## 確認したリソース

| リソース | 名前/エンドポイント | 状態 |
|---|---|---|
| ECSクラスター | `quick-mcp-poc-cluster` | ACTIVE |
| ECSサービス | `app`(タスク定義 `quick-mcp-poc-app:2`) | ACTIVE, 1/1 running |
| ECSタスク仕様 | 0.25 vCPU / 512MB(Fargate)、イメージ`quick-mcp-poc:7d4b645`、コンテナポート3000 | - |
| ALB | `quick-mcp-poc-alb`(internal) | active |
| ALBターゲットグループ | `quick-mcp-poc-tg`(port 3000) | **healthy** |
| API Gateway | `quick-mcp-poc`(HTTP API) `https://f7g2osxo90.execute-api.ap-northeast-1.amazonaws.com` | 疎通確認OK |
| Cognito User Pool | `quick-mcp-poc-users`(`ap-northeast-1_GHGepizqR`) | 41ユーザー登録済み(実データ、未変更) |
| NATインスタンス | t3.nano × 2(AZ冗長、NAT Gatewayではなく自前EC2構成でコスト最適化) | - |
| DynamoDB | `quick-mcp-poc-users`(PROVISIONED 5RCU/5WCU) | - |

## 実施した確認(すべて読み取り専用/認証不要な範囲)

1. **ALBターゲットヘルスチェック**: `quick-mcp-poc-tg`のターゲット(10.0.10.4:3000)が`healthy`であることを確認
2. **OAuth Discoveryメタデータエンドポイント**への外部からのGETリクエスト → `200 OK`、正しいJSON(`authorization_servers`, `resource`)を返却
3. **認証なしでの`/mcp`へのPOSTリクエスト** → API Gatewayの JWT Authorizer によって`401 Unauthorized`で正しく拒否されることを確認(ECSコンテナまで到達する前にAPI Gateway層で弾かれている)

## 所見

- インフラ構成要素(VPC、ECS、ALB、API Gateway、Cognito、DynamoDB、KMS/SSM、NATインスタンス)はすべてTerraformでコード化済みで、`terraform/`配下の各`.tf`ファイルと一致する形で実際に稼働していることを確認できた。
- 認証レイヤー(API GatewayのJWT Authorizer)がアプリケーションコードに到達する前段でブロックしている設計であり、パターン3(AgentCore Runtime単体)で確認した「アプリコード内(`extractSub`/`resolveAuthorization`)で認可する」設計とは責務の分界点が異なる(詳細は[01-internal-architecture-comparison.md](./01-internal-architecture-comparison.md)参照)。
- 完全なエンドツーエンド(Cognitoログイン→JWT取得→MCP tools/list実行)の疎通確認は、実クライアントデータへの影響を避けるため今回は実施していない。実施する場合は、明確にテスト用と分かるCognitoユーザーを新規作成し、対応するDynamoDBレコードを追加する必要がある(既存の`quick-mcp-poc-users`テーブル・User Poolへの書き込みが発生する)。

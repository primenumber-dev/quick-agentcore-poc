# quick-mcp-poc

MCPサーバー(本リポジトリ)を Amazon Bedrock AgentCore Runtime にデプロイし、既存の API Gateway + ECS 構成と比較検証するプロジェクト。

## ドキュメント

- **[docs/00-handoff.md](./docs/00-handoff.md)** — 作業を再開・引き継ぐ場合はまずここ(前回セッションの状況、AWSアカウントの使い分け、既知のはまりどころ)
- **[docs/README.md](./docs/README.md)** — 検証レポート一式の目次(アーキテクチャ比較、コスト試算、セキュリティ/コンプライアンス検証、OAuth接続検証など)
- **[CLAUDE.md](./CLAUDE.md)** — このリポジトリで作業する際の注意点(AWSアカウントの取り扱い等)

以下はアプリケーション自体のセットアップ手順。

## Required

- Node.js v24+
- pnpm
- Docker

## Getting Started

```bash
cd server && pnpm install && cd ..
cd cli && pnpm install && cd ..

cp server/.env.example server/.env
cp cli/.env.example cli/.env
cp nginx/.env.example nginx/.env
# Fill in values in each .env file

docker compose up -d

PORT=8000 pnpm --filter quick-mcp-poc-server dev
```

## Seed Data

```bash
pnpm --filter quick-mcp-poc-cli cli invite-user tanaka@example.com '{"earthquake":"standard","crypto":"lite"}'

# List users (Cognito)
pnpm --filter quick-mcp-poc-cli cli list-users

# Update services for an existing user
pnpm --filter quick-mcp-poc-cli cli update-services <sub> '{"earthquake":"standard","crypto":"standard"}'
```

## MCP Client Setup (Claude Code)

```bash
# <client_id> is from: terraform output local_cognito_user_pool_client_id
claude mcp add quick-mcp-poc --transport http --callback-port 3000 --client-id <client_id> http://localhost:8080/mcp
```

## Deploy (Manual, pre-CI)

```bash
# 1. Docker build & push (from server/)
# --platform=linux/amd64 is required when building on Apple Silicon (arm64),
# otherwise Fargate (defaults to linux/amd64) fails with "exec format error".
TAG=$(git rev-parse --short HEAD)
ECR_URL=$(terraform -chdir=../terraform output -raw ecr_repository_url)
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${ECR_URL}
docker build --platform=linux/amd64 -t ${ECR_URL}:${TAG} .
docker push ${ECR_URL}:${TAG}

# 2. ECS deploy
cd ../ecspresso/app
IMAGE_TAG=${TAG} ecspresso deploy
```

## Secrets (SSM Parameter Store)

Secrets are committed as KMS CiphertextBlobs in `terraform/ssm.tf` (`local.ssm_parameters`)
and registered as SSM SecureString by `terraform apply`. ECS tasks pull them in via the
`secrets` block of the task definition (`/quick-mcp-poc/quick-api/{user,pass}` etc.).

```bash
# 1. Create the KMS key and parameter scaffolding (first apply)
terraform -chdir=terraform apply

# 2. Encrypt a value (interactive; copy the printed CiphertextBlob)
./terraform/scripts/encrypt-secret.sh

# 3. Paste the blob into local.ssm_parameters[<key>].payload in terraform/ssm.tf, then apply
terraform -chdir=terraform apply

# 4. Decrypt to verify
./terraform/scripts/decrypt-secret.sh
```

Non-sensitive values (e.g. `QUICK_API_BASE`) go into `local.ssm_plain_parameters`
and are registered as plain String parameters.

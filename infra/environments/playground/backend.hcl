# playground (883660531246) の backend 設定。
#
# terraform init -backend-config=backend.hcl で読み込む。
# Makefile の `make init ENV=playground` を使えば付け忘れない。
#
# 注意: このバケットはまだ存在しない。現在 playground の state は
# terraform-playground-pattern4/terraform.tfstate としてディスク上にのみ存在する
# (75 リソースの唯一の state)。移行手順は DELIVERY-BLOCKERS DB-05 を参照。
#
#   1. バージョニング + SSE + パブリックアクセスブロックを有効にしたバケットを作る
#   2. 既存の terraform.tfstate をこのディレクトリへコピーする
#   3. terraform init -backend-config=backend.hcl -migrate-state
#
# ロックは DynamoDB テーブルではなく S3 ネイティブ (use_lockfile) を使う。
# terraform/provider.tf:9 と揃えている。

bucket       = "tfstate-quick-mcp-poc-playground-883660531246"
key          = "playground/terraform.tfstate"
region       = "ap-northeast-1"
profile      = "quick-agentcore-poc-playground"
encrypt      = true
use_lockfile = true

# quick (納品先、QUICK 様アカウント) の backend 設定。
#
# 未作成のプレースホルダ。納品時に確定する値:
#   - bucket: アカウント ID を含む一意な名前にする
#   - profile: 納品先の AWS プロファイル名 (CI からは GitHub OIDC + AssumeRole に
#     置き換える。SSO トークンは apply 途中で失効する。00-handoff.md §18.5 参照)
#
# バケット作成には terraform/scripts/create-tfstate-bucket.sh を使うが、
# 現在プロファイル名が quick-poc-admin に固定されている (:5-6)。
# 引数化してから使うこと (DELIVERY-BLOCKERS DB-03)。

bucket       = "tfstate-quick-mcp-poc-quick-CHANGEME"
key          = "quick/terraform.tfstate"
region       = "ap-northeast-1"
profile      = "CHANGEME"
encrypt      = true
use_lockfile = true

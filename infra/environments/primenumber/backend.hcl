# primenumber (620369151795、本番相当) の backend 設定。
#
# このアカウントには実クライアントデータ (41 ユーザー) があり、書き込みは厳禁。
# plan までに留めること。CLAUDE.md の注意事項を参照。
#
# バケットは既存 (terraform/scripts/create-tfstate-bucket.sh で作成済み)。
# terraform/provider.tf:4-10 のハードコード値をそのまま引き写している。
#
# key を変更してはならない。理由は 2 つ:
#   1. 本番 state の移行になり、得るものが無い
#   2. ecspresso/app/ecspresso.yml:10 がこの S3 URL を直指ししているため壊れる
#      (DELIVERY-BLOCKERS DB-02)

bucket       = "terraform.tfstate.professional-services-quick-poc"
key          = "terraform.tfstate"
region       = "ap-northeast-1"
encrypt      = true
use_lockfile = true

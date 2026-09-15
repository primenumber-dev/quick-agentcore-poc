variable "name_prefix" {
  type        = string
  description = "リソース名の接頭辞。現行値 \"quick-mcp-poc\"。移行元 lambda.tf のLambda/IAM名はこの接頭辞のみで構成される。"
}

variable "resource_suffix" {
  type        = string
  description = "環境識別のための接尾辞。**本モジュールのリソース名には使わない**(移行元が suffix 無しのため。main.tf の locals 参照)。他モジュールとインタフェースを揃えるために受け取る。"
  default     = ""
}

variable "region" {
  type        = string
  description = "AWSリージョン。モジュール内で data.aws_region を使わない規約のため入力で受け取る。"
}

variable "account_id" {
  type        = string
  description = "AWSアカウントID。モジュール内で data.aws_caller_identity を使わない規約のため入力で受け取る。"
}

variable "lambda_source_dir" {
  type        = string
  description = "ビルド済みLambda成果物の親ディレクトリ。配下の dist/authorizer と dist/register を zip 化する(移行元 lambda.tf:24,30 の path.module 相対パス \"../lambda\" に相当)。"
}

variable "runtime" {
  type        = string
  description = "両Lambdaのランタイム(lambda.tf:63,149)。"
  default     = "nodejs22.x"
}

variable "authorizer_timeout" {
  type        = number
  description = "Authorizer Lambda のタイムアウト秒(lambda.tf:66)。"
  default     = 5
}

variable "register_timeout" {
  type        = number
  description = "Register Lambda のタイムアウト秒(lambda.tf:152)。"
  default     = 10
}

variable "log_retention_days" {
  type        = number
  description = "両LambdaのCloudWatch Logs保持日数(lambda.tf:86,173)。"
  default     = 90
}

variable "user_pool_id" {
  type        = string
  description = "CognitoユーザープールID。auth モジュールの user_pool_id 出力を渡す(lambda.tf:70,156)。"
}

variable "user_pool_arn" {
  type        = string
  description = "CognitoユーザープールARN。register Lambda の cognito-idp 権限のリソース指定(lambda.tf:121)。"
}

variable "resource_server_identifier" {
  type        = string
  description = "Cognito resource server の identifier。REQUIRED_SCOPE は末尾に \"/invoke\" を付けて組み立てる(lambda.tf:71,72,157)。auth モジュールの出力を渡すこと。"
}

variable "dcr_table_name" {
  type        = string
  description = "DCR台帳・テナント台帳のDynamoDBテーブル名(lambda.tf:8)。terraform管理外の既存テーブル(docs/19 §2.1 F12)。現行値 \"quick-mcp-poc-users\"。"
}

variable "dcr_table_arn" {
  type        = string
  description = "上記テーブルのARN(lambda.tf:9)。移行元はアカウントID 883660531246 を含むリテラルだった。環境ルートで region + account_id + テーブル名から組み立てて渡すこと。"
}

variable "origin_verify_secret" {
  type        = string
  sensitive   = true
  description = <<-EOT
    CloudFront が付与する X-Origin-Verify ヘッダの検証値(移行元 lambda.tf:78 の
    random_password.origin_verify.result)。

    docs/23 §1.3: この random_password は dcr と edge-waf の双方から参照されるため
    **環境ルートで宣言し**、両モジュールへ入力として渡す。ルートでのアドレスが
    random_password.origin_verify のまま変わらないので moved ブロックは書かないこと。
    誤って再生成すると稼働中のCloudFrontとAuthorizerの間に値の不一致窓が開き、
    全リクエストが弾かれる。
  EOT
}

variable "deny_mode" {
  type        = string
  description = "Authorizer の拒否方法(lambda.tf:75、DENY_MODE)。docs/19 §2.4-a の401化試行。"
  default     = "throw"
}

variable "require_audience_for_user_tokens" {
  type        = string
  description = "ユーザートークンに aud 検証を要求するか(lambda.tf:76)。Lambda環境変数のため文字列 \"true\"/\"false\"。"
  default     = "false"
}

variable "enforce_origin_verify" {
  type        = string
  description = "X-Origin-Verify の不一致を拒否するか(lambda.tf:79)。観測モード \"false\" から開始する。true にできない理由は cloudfront_waf.tf:6-9 / docs/23 §5 F4 を参照。"
  default     = "false"
}

variable "allowed_redirect_hosts" {
  type        = string
  description = "DCR登録時に許可する redirect_uri のホスト(lambda.tf:160)。カンマ区切り。MVPのアローリスト(docs/08 §2.4)。"
  default     = "claude.ai,claude.com"
}

variable "default_token_endpoint_auth_method" {
  type        = string
  description = "DCRクライアントの既定 token_endpoint_auth_method(lambda.tf:162)。"
  default     = "none"
}

variable "max_dcr_clients" {
  type        = string
  description = "DCRクライアント数の上限(lambda.tf:163)。Lambda環境変数のため文字列。"
  default     = "200"
}

variable "max_registrations_per_ip_per_minute" {
  type        = string
  description = "IP単位の登録レート制限(lambda.tf:164)。Lambda環境変数のため文字列。"
  default     = "5"
}

variable "access_token_validity_minutes" {
  type        = string
  description = "DCRクライアントに設定するアクセストークン有効期間(分、lambda.tf:165)。Lambda環境変数のため文字列。"
  default     = "60"
}

variable "apply_managed_login_branding" {
  type        = string
  description = "DCRクライアントに Managed Login ブランディングを割り当てるか(lambda.tf:166)。無いとログイン画面が出ない(CL-03)。"
  default     = "true"
}

variable "tags" {
  type        = map(string)
  description = "追加タグ。移行元 lambda.tf は個別のtagsを持たず provider の default_tags に依存していたため、現状はどのリソースにも適用していない。差分ゼロ移行の完了後に適用する。"
  default     = {}
}

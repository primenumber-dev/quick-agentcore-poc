variable "name_prefix" {
  type        = string
  description = "全リソース名の共通接頭辞。移行元では約40行に直書きされていた \"quick-mcp-poc\"(docs/23 §3.1)。"
  default     = "quick-mcp-poc"
}

variable "resource_suffix" {
  type        = string
  description = "環境識別のためのリソース名接尾辞。playground は \"-pattern4-verify\"、primenumber は \"\"(docs/23 §3.1)。本モジュールでは既存stateと差分ゼロを保つため名前生成には既定で使わず、環境側で明示した名前変数に反映させる。"
  default     = ""
}

variable "region" {
  type        = string
  description = "API Gateway・Cognito ドメイン・metadata REST API のエンドポイント組み立てに使うリージョン。モジュール内で data.aws_region を引かないため入力で受ける(apigateway.tf:111,118,125,133)。"
}

variable "api_name" {
  type        = string
  description = "HTTP API(aws_apigatewayv2_api.main)の名前。VPC Link 名にも同じ値を使う(apigateway.tf:58, :102)。"
  default     = "quick-mcp-poc"
}

variable "metadata_api_name" {
  type        = string
  description = "メタデータ用 REST API の名前。null の場合 \"<name_prefix>-metadata\" を使う(apigateway.tf:30)。"
  default     = null
}

variable "metadata_stage_name" {
  type        = string
  description = "メタデータ REST API のステージ名(apigateway.tf:54)。"
  default     = "v1"
}

variable "access_log_group_name" {
  type        = string
  description = "API Gateway アクセスログの CloudWatch Logs グループ名(apigateway.tf:64)。AUTHZ-04 の監査証跡。"
  default     = "/quick-mcp-poc/apigw-access"
}

variable "access_log_retention_days" {
  type        = number
  description = "アクセスログの保持日数(apigateway.tf:65)。"
  default     = 90
}

variable "register_throttle" {
  type = object({
    burst = number
    rate  = number
  })
  description = "未認証 POST /register のスロットリング(apigateway.tf:96-97)。DCR の乱用対策(docs/08 §2.4)。"
  default = {
    burst = 5
    rate  = 2
  }
}

variable "authorizer_ttl_seconds" {
  type        = number
  description = "Lambda REQUEST Authorizer の結果キャッシュ秒数(apigateway.tf:169)。0 以外にすると `cli delete-client` による失効が最大その秒数だけ遅延する。"
  default     = 0
}

variable "service_documentation_url" {
  type        = string
  description = "AS メタデータの service_documentation(apigateway.tf:20)。"
  default     = "https://github.com/primenumber-dev/quick-agentcore-poc"
}

variable "alb_security_group_id" {
  type        = string
  description = "VPC Link に付与する ALB のセキュリティグループID(旧: aws_security_group.alb.id、apigateway.tf:103)。"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "VPC Link を配置するプライベートサブネットID(旧: [for s in aws_subnet.private : s.id]、apigateway.tf:104)。"
}

variable "alb_listener_arn" {
  type        = string
  description = "VPC Link 経由で繋ぐ ALB リスナーの ARN(旧: aws_lb_listener.http.arn、apigateway.tf:139)。"
}

variable "cognito_domain" {
  type        = string
  description = "Cognito ホステッドUIのドメインプレフィックス(旧: aws_cognito_user_pool_domain.main.domain、apigateway.tf:118,125,133)。"
}

variable "cognito_issuer_url" {
  type        = string
  description = "Cognito ユーザープールの issuer URL。jwks_uri と(enable_dcr=false 時の)JWT Authorizer issuer に使う(apigateway.tf:4、terraform/apigateway.tf:97)。"
}

variable "resource_server_identifier" {
  type        = string
  description = "Cognito resource server の identifier。scopes_supported と openapi.yaml のテンプレート変数に展開される(apigateway.tf:17,24)。docs/23 §1.2 のとおり state の実値をコピーすること。**JWT Authorizer の audience に渡してはならない**。"
}

variable "cognito_app_client_id" {
  type        = string
  description = "enable_dcr=false(旧世代)の JWT Authorizer に渡すアプリクライアントID(terraform/apigateway.tf:96)。enable_dcr=true では未使用。"
  default     = null
}

variable "authorizer_invoke_arn" {
  type        = string
  description = "DCR Lambda Authorizer の invoke_arn(apigateway.tf:163)。"
  default     = null
}

variable "authorizer_function_name" {
  type        = string
  description = "DCR Lambda Authorizer の関数名。aws_lambda_permission の対象(lambda.tf:92)。"
  default     = null
}

variable "register_invoke_arn" {
  type        = string
  description = "DCR Register Lambda の invoke_arn(apigateway.tf:155)。"
  default     = null
}

variable "register_function_name" {
  type        = string
  description = "DCR Register Lambda の関数名。aws_lambda_permission の対象(lambda.tf:179)。"
  default     = null
}

variable "enable_dcr" {
  type        = bool
  description = "true で DCR 世代(Lambda REQUEST Authorizer + /register + /revoke、apigateway.tf:94-103 相当)、false で旧世代(Cognito JWT Authorizer のみ、terraform/apigateway.tf:84-99 相当)。primenumber は当初 false で現行ライブ状態と差分ゼロにし、世代マージを意図的な別変更として切り出す(docs/23 §3.2、§5 F1)。"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "全リソースへ付与する追加タグ。provider の default_tags に上乗せされる。"
  default     = {}
}

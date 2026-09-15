# スタブ。リソース定義は存在しない。理由は README.md を参照。
# 以下は「実装時にこうなる想定」のインタフェース宣言であり、現時点でどれも使われていない。

variable "name_prefix" {
  type        = string
  description = "リソース名の接頭辞。現行値 \"quick-mcp-poc\"。"
  default     = "quick-mcp-poc"
}

variable "resource_suffix" {
  type        = string
  description = "環境識別のための接尾辞。playground は \"-pattern4-verify\"、本番相当は \"\"。"
  default     = ""
}

variable "region" {
  type        = string
  description = "AgentCore Runtime を作成するAWSリージョン。モジュール内で data.aws_region を使わない規約のため入力で受け取る。"
  default     = null
}

variable "account_id" {
  type        = string
  description = "AWSアカウントID。モジュール内で data.aws_caller_identity を使わない規約のため入力で受け取る。"
  default     = null
}

variable "container_image_uri" {
  type        = string
  description = "AgentCore Runtime が起動するMCPサーバのコンテナイメージURI(ECR)。"
  default     = null
}

variable "user_pool_id" {
  type        = string
  description = "受信JWTを検証する Cognito ユーザープールID。auth モジュールの出力を渡す想定。"
  default     = null
}

variable "allowed_client_ids" {
  type        = list(string)
  description = "AgentCore Runtime の JWT authorizer が許可するクライアントIDの一覧。"
  default     = []
}

variable "allowed_audience" {
  type        = list(string)
  description = "AgentCore Runtime の JWT authorizer が許可する audience の一覧。"
  default     = []
}

variable "network_mode" {
  type        = string
  description = "AgentCore Runtime のネットワークモード(\"PUBLIC\" または \"VPC\")。VPCモードの参考実装は docs/terraform-examples/agentcore-vpc-mode/main.tf。"
  default     = "PUBLIC"
}

variable "subnet_ids" {
  type        = list(string)
  description = "network_mode が \"VPC\" のときに使うサブネットID。"
  default     = []
}

variable "security_group_ids" {
  type        = list(string)
  description = "network_mode が \"VPC\" のときに使うセキュリティグループID。"
  default     = []
}

variable "environment_variables" {
  type        = map(string)
  description = "Runtime コンテナに渡す環境変数(TABLE_NAME など)。"
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "全リソースに付与するタグ。"
  default     = {}
}

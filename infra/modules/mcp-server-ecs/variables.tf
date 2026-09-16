variable "name_prefix" {
  type        = string
  description = "全リソース名の先頭に付く共通プレフィックス(例: quick-mcp-poc)。"
}

variable "resource_suffix" {
  type        = string
  description = "環境識別用のサフィックス(例: -pattern4-verify)。注意: 移行元 terraform-playground-pattern4/ecs.tf・alb.tf のリソース名は接尾辞を含まず \"quick-mcp-poc-cluster\" 等の素の形である。既存stateを引き継ぐ環境では空文字を渡し、名前をバイト等価に保つこと。"
  default     = ""
}

variable "vpc_id" {
  type        = string
  description = "ECS/ALBのセキュリティグループとターゲットグループを置くVPCのID。移行元: ecs.tf:3、alb.tf:3,44 の aws_vpc.main.id。"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "内部ALBを配置するプライベートサブネットIDのリスト。移行元: alb.tf:25。"
}

variable "container_port" {
  type        = number
  description = "アプリコンテナの待ち受けポート。ECS SGのingress、ターゲットグループのportに使う。移行元: ecs.tf:6-7、alb.tf:42。"
  default     = 3000
}

variable "health_check" {
  type = object({
    interval            = number
    timeout             = number
    healthy_threshold   = number
    unhealthy_threshold = number
    path                = string
    matcher             = string
  })
  description = "ターゲットグループのヘルスチェック設定。移行元: alb.tf:47-54。"
  default = {
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    path                = "/health"
    matcher             = "200"
  }
}

variable "alb_ingress_cidrs" {
  type        = list(string)
  description = "内部ALBのHTTP(80)ingressを許可するCIDRのリスト。移行元 alb.tf:9 は 10.0.0.0/16 を直書きしていた。通常はVPC CIDR([module.network.vpc_cidr])を渡す。"
}

variable "log_retention_days" {
  type        = number
  description = "ECSコンテナログのCloudWatch Logs保持日数。移行元: ecs.tf:123。"
  default     = 90
}

variable "ssm_path_prefix" {
  type        = string
  description = "タスクが参照するSSMパラメータの共通プレフィックス(先頭スラッシュあり・末尾スラッシュなし。例: /quick-mcp-poc)。IAMポリシーのresourcesに使う。移行元: ecs.tf:108 の /quick-mcp-poc/*。"
}

variable "ssm_kms_key_arn" {
  type        = string
  description = "SSM SecureString の復号に使うKMSキーのARN。parameters モジュールの kms_key_arn 出力を渡す。移行元: ecs.tf:116 の aws_kms_key.ssm.arn。"
}

variable "region" {
  type        = string
  description = "SSMパラメータARNの組み立てに使うリージョン。モジュール内で data.aws_region を引かず環境ルートから受け取る(移行元 ecs.tf:108 のデータソース参照は廃止)。"
}

variable "account_id" {
  type        = string
  description = "SSMパラメータARNの組み立てに使うAWSアカウントID。モジュール内で data.aws_caller_identity を引かず環境ルートから受け取る(移行元 ecs.tf:108 のデータソース参照は廃止)。"
}

# 移行元 ecs.tf:83-89 は2要素だった。
#   - aws_dynamodb_table.mcp_users.arn(Terraform管理のテーブル)
#   - arn:aws:dynamodb:ap-northeast-1:883660531246:table/quick-mcp-poc-users
#     (アカウントIDを直書きした、AgentCore Runtime検証で作成済みの既存テーブル)
# 後者の直書きを排するため、両方をこの1変数のリストとして環境ルートから渡す。
variable "dynamodb_table_arns" {
  type        = list(string)
  description = "アプリタスクロールに dynamodb:GetItem を許可するテーブルARNのリスト。移行元: ecs.tf:84 と ecs.tf:88(アカウントID直書き)の両方を置き換える。"
}

# 以下3つは現時点でこのモジュール内のどのリソースからも参照されていない。
# ECSサービス/タスク定義は ecspresso(ecspresso/app/ecs-task-def.json:5-6、
# ecs-service-def.json:4)が管理しているため。
# 将来 ecspresso → Terraform 移行(docs/23 §5 F2 / 納品ブロッカー2)で
# aws_ecs_task_definition・aws_ecs_service をこのモジュールに取り込む際の受け皿として
# 先に宣言しておく。移行時に既定値が現行の ecspresso 設定と一致していることを確認すること。
variable "task_cpu" {
  type        = string
  description = "[未使用・将来のecspresso移行用] Fargateタスクの CPU ユニット。現行値は ecspresso/app/ecs-task-def.json:5。"
  default     = "256"
}

variable "task_memory" {
  type        = string
  description = "[未使用・将来のecspresso移行用] Fargateタスクのメモリ(MiB)。現行値は ecspresso/app/ecs-task-def.json:6。"
  default     = "512"
}

variable "desired_count" {
  type        = number
  description = "[未使用・将来のecspresso移行用] ECSサービスの希望タスク数。現行値は ecspresso/app/ecs-service-def.json:4。"
  default     = 1
}

variable "tags" {
  type        = map(string)
  description = "全リソースに付与する共通タグ。"
  default     = {}
}

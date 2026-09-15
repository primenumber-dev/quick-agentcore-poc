# quick の環境ルート。
#
# 移行元: terraform-playground-pattern4/ (13 ファイル、1642 行、75 リソース)。
# 移行元ディレクトリはロールバック参照として残置しており、削除しないこと。
#
# 適用前に必ず読むこと: docs/23-weekly-verification-plan-week6.md §4
#   受け入れ基準は plan が 0 to add, 0 to change, 0 to destroy になること。
#   例外は aws_api_gateway_deployment.metadata の 1 件のみ。
#   aws_cloudfront_distribution.edge に -/+ が出たら即中断。

terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.24"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # App タグは移行元でも provider の default_tags で付与されていた
  # (provider.tf:22-28)。各リソースの tags 属性には入っていないため、
  # モジュールへは tags = {} を渡し、ここで維持する。
  # モジュールへ非空の tags を渡すと全リソースにタグ追加の差分が出る。
  default_tags {
    tags = var.default_tags
  }
}

# CLOUDFRONT スコープの WAF は us-east-1 にしか置けない。
# エイリアス名 aws.use1 は変更しないこと。edge-waf モジュール内の
# provider = aws.use1 の指定と対応しており、ずれると Terraform が
# Web ACL の再作成を提案し、稼働中のディストリビューションから外れる。
provider "aws" {
  alias   = "use1"
  region  = "us-east-1"
  profile = var.aws_profile

  default_tags {
    tags = var.default_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # DCR Lambda が実際に読むテーブル。Terraform 管理外のため ARN を組み立てる
  # (移行元 lambda.tf:9 はアカウント ID 883660531246 を直書きしていた)。
  dcr_table_arn = "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/${var.dcr_table_name}"
}

# --- 環境ルートに据え置くリソース ---

# dcr と edge-waf の両方が参照するため、モジュールではなくここに置く。
# モジュールのどちらかに置くと edge-waf -> dcr -> api-gateway -> edge-waf の
# 循環になる (docs/23 §1.3)。
#
# アドレスが移行元と同じなので moved ブロックは不要。書いてはならない。
# ここから消すと destroy され、再作成で X-Origin-Verify がローテートする。
# 稼働中の CloudFront と Lambda Authorizer の間に不一致窓が開き、
# バイパス対策が一時的に全リクエストを弾く。
resource "random_password" "origin_verify" {
  length  = var.origin_verify_length
  special = false
}

# 検証用テーブル。環境ごとに存在有無が異なるためモジュール化していない。
# 本番は 41 ユーザーの実データがあり Terraform 管理外 (DELIVERY-BLOCKERS DB-09)。
resource "aws_dynamodb_table" "mcp_users" {
  name           = var.dynamodb_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "PK"

  attribute {
    name = "PK"
    type = "S"
  }

  tags = {
    Name = var.dynamodb_table_name
  }
}

# --- モジュール ---
#
# module ブロックに depends_on / count / for_each を付けないこと。
# いずれもモジュールを単一グラフノードに潰し、存在しないはずの循環を作る
# (docs/23 §1.4)。任意化はモジュール内リソースの count で行っている。

module "network" {
  source = "../../modules/network"

  name_prefix = var.name_prefix
  # network のリソース名に接尾辞は付かない。付けるとセキュリティグループ名が
  # 変わり destroy/create になる (docs/23 §3.1)。
  resource_suffix = ""

  vpc_cidr            = var.vpc_cidr
  public_subnets      = var.public_subnets
  private_subnets     = var.private_subnets
  nat_instance_type   = var.nat_instance_type
  nat_ami_name_filter = var.nat_ami_name_filter
  nat_ami_id          = var.nat_ami_id

  tags = {}
}

module "parameters" {
  source = "../../modules/parameters"

  name_prefix     = var.name_prefix
  resource_suffix = var.resource_suffix # ssm / kms には接尾辞が付く
  ssm_path_prefix = var.ssm_path_prefix
  kms_alias_name  = var.kms_alias_name

  plain_parameters     = var.ssm_plain_parameters
  encrypted_parameters = var.ssm_encrypted_parameters
  plaintext_parameters = var.ssm_plaintext_parameters

  tags = {}
}

module "mcp_server_ecs" {
  source = "../../modules/mcp-server-ecs"

  name_prefix     = var.name_prefix
  resource_suffix = "" # IAM ロール名・SG 名・TG 名に接尾辞は付かない

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  alb_ingress_cidrs  = [var.vpc_cidr]

  container_port     = var.container_port
  health_check       = var.health_check
  log_retention_days = var.log_retention_days

  ssm_path_prefix = module.parameters.ssm_path_prefix
  ssm_kms_key_arn = module.parameters.kms_key_arn

  region     = var.aws_region
  account_id = local.account_id

  # 移行元 ecs.tf:84,88 は 2 つのテーブルを許可していた。Terraform が作る
  # 検証用テーブルと、アプリが実際に読む AgentCore 検証時のテーブルの両方。
  # 後者はアカウント ID 直書きだった。
  dynamodb_table_arns = [
    aws_dynamodb_table.mcp_users.arn,
    local.dcr_table_arn,
  ]

  tags = {}
}

module "auth" {
  source = "../../modules/auth"

  name_prefix     = var.name_prefix
  resource_suffix = var.resource_suffix # ユーザープール名には接尾辞が付く
  region          = var.aws_region

  user_pool_name = var.user_pool_name
  domain_prefix  = var.cognito_domain_prefix
  callback_urls  = var.cognito_callback_urls

  # 移行元は API Gateway のエンドポイントから導出していた (cognito.tf:50)。
  # 変数化した理由は循環回避ではなく、apply 前に値が確定しないことと、
  # API 再作成時に resource server とスコープが連鎖再作成され、発行済み
  # DCR クライアントのスコープ付与が全滅することを防ぐため (docs/23 §1.2)。
  #
  # 値は state から読んでコピーすること。手打ち禁止。
  resource_server_identifier = var.resource_server_identifier
  resource_server_name       = var.resource_server_name

  explicit_auth_flows = var.cognito_explicit_auth_flows
  enable_local_pool   = var.enable_local_pool

  local_pool_domain_prefix              = var.local_pool_domain_prefix
  local_pool_callback_urls              = var.local_pool_callback_urls
  local_pool_resource_server_identifier = var.local_pool_resource_server_identifier

  tags = {}
}

module "dcr" {
  source = "../../modules/dcr"

  name_prefix     = var.name_prefix
  resource_suffix = "" # Lambda 名・IAM ロール名に接尾辞は付かない
  region          = var.aws_region
  account_id      = local.account_id

  lambda_source_dir  = var.lambda_source_dir
  runtime            = var.lambda_runtime
  authorizer_timeout = var.dcr_authorizer_timeout
  register_timeout   = var.dcr_register_timeout
  log_retention_days = var.log_retention_days

  user_pool_id               = module.auth.user_pool_id
  user_pool_arn              = module.auth.user_pool_arn
  resource_server_identifier = var.resource_server_identifier

  dcr_table_name = var.dcr_table_name
  dcr_table_arn  = local.dcr_table_arn

  origin_verify_secret = random_password.origin_verify.result

  deny_mode                           = var.dcr_deny_mode
  require_audience_for_user_tokens    = var.dcr_require_audience_for_user_tokens
  enforce_origin_verify               = var.dcr_enforce_origin_verify
  allowed_redirect_hosts              = var.dcr_allowed_redirect_hosts
  default_token_endpoint_auth_method  = var.dcr_default_token_endpoint_auth_method
  max_dcr_clients                     = var.dcr_max_clients
  max_registrations_per_ip_per_minute = var.dcr_max_registrations_per_ip_per_minute
  access_token_validity_minutes       = var.dcr_access_token_validity_minutes
  apply_managed_login_branding        = var.dcr_apply_managed_login_branding

  tags = {}
}

module "api_gateway" {
  source = "../../modules/api-gateway"

  name_prefix     = var.name_prefix
  resource_suffix = "" # API 名・VPC Link 名に接尾辞は付かない
  region          = var.aws_region

  api_name                  = var.api_name
  access_log_group_name     = var.apigw_access_log_group_name
  access_log_retention_days = var.log_retention_days
  register_throttle         = var.register_throttle
  authorizer_ttl_seconds    = var.authorizer_ttl_seconds
  service_documentation_url = var.service_documentation_url

  alb_security_group_id = module.mcp_server_ecs.alb_security_group_id
  private_subnet_ids    = module.network.private_subnet_ids
  alb_listener_arn      = module.mcp_server_ecs.alb_listener_arn

  cognito_domain             = module.auth.domain
  cognito_issuer_url         = module.auth.issuer_url
  cognito_app_client_id      = module.auth.user_pool_client_id
  resource_server_identifier = var.resource_server_identifier

  authorizer_invoke_arn    = module.dcr.authorizer_invoke_arn
  authorizer_function_name = module.dcr.authorizer_function_name
  register_invoke_arn      = module.dcr.register_invoke_arn
  register_function_name   = module.dcr.register_function_name

  enable_dcr = var.enable_dcr

  tags = {}
}

module "edge_waf" {
  source = "../../modules/edge-waf"

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  name_prefix     = var.name_prefix
  resource_suffix = "" # 稼働中の Web ACL 名は quick-mcp-poc-edge
  enabled         = var.enable_edge_waf

  api_endpoint         = module.api_gateway.api_endpoint
  origin_verify_secret = random_password.origin_verify.result

  waf_mode                        = var.waf_mode
  managed_rule_groups             = var.waf_managed_rule_groups
  common_rule_set_count_overrides = var.waf_common_rule_set_count_overrides

  # この 2 つは 1 つの判断の両半分であり、片方だけ動かすと week5 で見つけた
  # 日本語長文の UTF-8 偽陽性が再発する (cloudfront_waf.tf:65-67)。
  body_inspection_limit = var.waf_body_inspection_limit
  body_size_limit_bytes = var.waf_body_size_limit_bytes

  geo_observe_countries  = var.waf_geo_observe_countries
  price_class            = var.cloudfront_price_class
  waf_log_retention_days = var.log_retention_days

  tags = {}
}

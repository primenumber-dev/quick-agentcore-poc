# AgentCore Runtime VPCモード構成のTerraform例
#
# 注意: このファイルはリファレンス実装であり、terraform/(本番相当アカウントのstate)には含めていない。
# 2026-08-21にplaygroundアカウントでAWS CLI(update-agent-runtime等)により実機構築・検証した内容を
# Terraformコードとして書き直したもの。実際に適用する場合は、別途state/backendを用意し、
# providerブロックのregion・profileを対象アカウントに合わせて調整すること。
#
# 検証済みの実機構成: docs/05-security-compliance-verification.md §4.1.1、docs/07-vpc-waf-cost-verification.md §3 参照

terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.24"
    }
  }
}

variable "region" {
  default = "ap-northeast-1"
}

variable "agent_runtime_id" {
  description = "既存のAgentCore RuntimeのID(create-agent-runtimeで別途作成済みのものを前提とする)"
  type        = string
}

variable "container_uri" {
  description = "ECRのコンテナイメージURI"
  type        = string
}

variable "execution_role_arn" {
  description = "AgentCore Runtime実行ロールARN"
  type        = string
}

variable "cognito_discovery_url" {
  type = string
}

variable "cognito_allowed_client_ids" {
  type = list(string)
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      App = "quick-mcp-poc"
    }
  }
}

# --- VPC本体 ---
# enable_dns_support / enable_dns_hostnames は、Interfaceエンドポイントのプライベートdns解決に必須。
# CLIで実機検証した際、この2属性が有効化されていないとcreate-vpc-endpoint(Interface型)が
# InvalidParameterで失敗した(docs/07-vpc-waf-cost-verification.md §3.2参照)。
resource "aws_vpc" "agentcore_verification" {
  cidr_block           = "10.99.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "quick-mcp-poc-verification-vpc"
  }
}

resource "aws_subnet" "private" {
  for_each = {
    "1a" = { cidr_block = "10.99.0.0/26", availability_zone = "${var.region}a" }
    "1c" = { cidr_block = "10.99.0.64/26", availability_zone = "${var.region}c" }
  }

  vpc_id            = aws_vpc.agentcore_verification.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    Name = "quick-mcp-poc-verification-private-${each.key}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.agentcore_verification.id

  tags = {
    Name = "quick-mcp-poc-verification-rtb"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# --- セキュリティグループ ---
# Runtime ENIとVPCエンドポイント(Interface型)のENIが同じSGを使うため、
# 自己参照で443番ポートを許可しないと、エンドポイント経由の通信がブロックされる。
resource "aws_security_group" "agentcore_verification" {
  name        = "quick-mcp-poc-verification-sg"
  description = "quick-mcp-poc AgentCore Runtime VPC mode verification"
  vpc_id      = aws_vpc.agentcore_verification.id

  tags = {
    Name = "quick-mcp-poc-verification-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "self_https" {
  security_group_id            = aws_security_group.agentcore_verification.id
  referenced_security_group_id = aws_security_group.agentcore_verification.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.agentcore_verification.id
  ip_protocol        = "-1"
  cidr_ipv4          = "0.0.0.0/0"
}

# --- VPCエンドポイント ---
# S3 / DynamoDBはGateway型(無料、ルートテーブルに紐付け)。
# ECR API / DKRはInterface型(時間課金あり)で、コンテナイメージのpullに必須。
# 2026年5月5日ロールアウト以降に作成されたRuntimeは、service-managed S3 Gatewayを経由せず
# 全ネットワークアクセスが自社VPC設定に従う仕様のため、これらのエンドポイントが無いと
# イメージpullに失敗し、Runtimeが`UPDATING`のまま進行しなくなる(実機で確認済み)。
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.agentcore_verification.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "quick-mcp-poc-verification-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.agentcore_verification.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "quick-mcp-poc-verification-dynamodb-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.agentcore_verification.id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type    = "Interface"
  subnet_ids           = [for s in aws_subnet.private : s.id]
  security_group_ids   = [aws_security_group.agentcore_verification.id]
  private_dns_enabled  = true

  tags = {
    Name = "quick-mcp-poc-verification-ecr-api"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.agentcore_verification.id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type    = "Interface"
  subnet_ids           = [for s in aws_subnet.private : s.id]
  security_group_ids   = [aws_security_group.agentcore_verification.id]
  private_dns_enabled  = true

  tags = {
    Name = "quick-mcp-poc-verification-ecr-dkr"
  }
}

# --- AgentCore Runtime本体をVPCモードへ切り替える ---
#
# 【重要な注意】この執筆時点(2026-08-21)で、Terraform AWS providerの`aws_bedrockagentcore_runtime`
# リソース(または同等のリソース)がnetworkConfiguration.networkMode=VPCの更新をどこまでカバーしているかは
# 未確認。実機検証(§3)は素のAWS CLI(update-agent-runtime)で行っており、Terraformネイティブリソースでの
# 動作は検証していない。適用前に、使用するprovider version添付のドキュメントでスキーマを必ず確認すること。
#
# ネイティブリソースが未対応/スキーマ不一致の場合のフォールバックとして、
# 実機で検証済みのAWS CLIコマンドをnull_resource + local-execでラップする方法を下に示す
# (こちらは実機で動作確認済みの構成そのもの)。

# 案A: ネイティブリソース(要スキーマ確認)
# resource "aws_bedrockagentcore_runtime" "quick_mcp_poc" {
#   agent_runtime_id = var.agent_runtime_id
#
#   agent_runtime_artifact {
#     container_configuration {
#       container_uri = var.container_uri
#     }
#   }
#
#   role_arn = var.execution_role_arn
#
#   network_configuration {
#     network_mode = "VPC"
#     network_mode_config {
#       security_groups = [aws_security_group.agentcore_verification.id]
#       subnets          = [for s in aws_subnet.private : s.id]
#     }
#   }
#
#   protocol_configuration {
#     server_protocol = "MCP"
#   }
#
#   request_header_configuration {
#     request_header_allowlist = ["x-cognito-sub", "Authorization"]
#   }
#
#   authorizer_configuration {
#     custom_jwt_authorizer {
#       discovery_url   = var.cognito_discovery_url
#       allowed_clients = var.cognito_allowed_client_ids
#       allowed_scopes  = ["openid", "mcp/invoke"]
#     }
#   }
#
#   metadata_configuration {
#     require_mmds_v2 = true
#   }
# }

# 案B: AWS CLIラップ(実機検証済みの構成そのもの。案Aが使えない場合のフォールバック)
resource "null_resource" "agentcore_runtime_vpc_mode" {
  triggers = {
    security_group = aws_security_group.agentcore_verification.id
    subnets        = join(",", [for s in aws_subnet.private : s.id])
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws bedrock-agentcore-control update-agent-runtime \
        --agent-runtime-id ${var.agent_runtime_id} \
        --agent-runtime-artifact '{"containerConfiguration":{"containerUri":"${var.container_uri}"}}' \
        --role-arn ${var.execution_role_arn} \
        --network-configuration '{"networkMode":"VPC","networkModeConfig":{"securityGroups":["${aws_security_group.agentcore_verification.id}"],"subnets":${jsonencode([for s in aws_subnet.private : s.id])}}}' \
        --protocol-configuration '{"serverProtocol":"MCP"}' \
        --request-header-configuration '{"requestHeaderAllowlist":["x-cognito-sub","Authorization"]}' \
        --authorizer-configuration '{"customJWTAuthorizer":{"discoveryUrl":"${var.cognito_discovery_url}","allowedClients":${jsonencode(var.cognito_allowed_client_ids)},"allowedScopes":["openid","mcp/invoke"]}}' \
        --region ${var.region}
    EOT
  }

  depends_on = [
    aws_vpc_endpoint.ecr_api,
    aws_vpc_endpoint.ecr_dkr,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.dynamodb,
    aws_vpc_security_group_ingress_rule.self_https,
  ]
}

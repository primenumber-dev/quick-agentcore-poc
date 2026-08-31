# playgroundアカウント(883660531246)専用。本番相当のterraform/とはstate・backendを完全に分離している。
# パターン4(API Gateway + ECS)のコールドスタート比較検証のためだけに、既存のterraform/を複製・移植したもの。

terraform {
  required_version = "~> 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.24"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "quick-agentcore-poc-playground"

  default_tags {
    tags = {
      App = "quick-mcp-poc-pattern4-verification"
    }
  }
}

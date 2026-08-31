terraform {
  required_version = "~> 1.15.0"

  backend "s3" {
    bucket       = "terraform.tfstate.professional-services-quick-poc"
    region       = "ap-northeast-1"
    key          = "terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.24"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"

  default_tags {
    tags = {
      App = "quick-mcp-poc"
    }
  }
}

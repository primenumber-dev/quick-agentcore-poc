# 本番相当のterraform/ssm.tfを簡略化して移植。
# 実際のQUICK APIシークレットは持たないため、ダミー値のプレースホルダーを登録する
# (AgentCore Runtime側の検証と同様、`QUICK_API_USER / QUICK_API_PASS are not set`相当の
# 想定される失敗に到達することが目的で、実APIへの接続自体は範囲外)。

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "ssm" {
  description         = "KMS key for SSM Parameter Store in quick-mcp-poc-pattern4-verify"
  enable_key_rotation = true

  tags = {
    Name = "quick-mcp-poc-pattern4-verify-ssm-kms-key"
  }
}

resource "aws_kms_alias" "ssm" {
  name          = "alias/quick-mcp-poc-pattern4-verify-ssm"
  target_key_id = aws_kms_key.ssm.key_id
}

resource "aws_ssm_parameter" "quick_api_base" {
  name        = "/quick-mcp-poc/quick-api/base"
  type        = "String"
  value       = "https://qr1.devmarket.myquick.net/home/member/wam_mxlgn/common/docs/api/"
  description = "QUICK API base URL(検証用、本番と同一の公開値)"
}

resource "aws_ssm_parameter" "quick_api_user" {
  name        = "/quick-mcp-poc/quick-api/user"
  type        = "SecureString"
  key_id      = aws_kms_key.ssm.id
  value       = "placeholder-not-a-real-credential"
  description = "QUICK API basic auth user(プレースホルダー、実credentialではない)"
}

resource "aws_ssm_parameter" "quick_api_pass" {
  name        = "/quick-mcp-poc/quick-api/pass"
  type        = "SecureString"
  key_id      = aws_kms_key.ssm.id
  value       = "placeholder-not-a-real-credential"
  description = "QUICK API basic auth password(プレースホルダー、実credentialではない)"
}

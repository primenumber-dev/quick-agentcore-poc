data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "ssm" {
  description         = "KMS key for SSM Parameter Store in quick-mcp-poc"
  enable_key_rotation = true

  tags = {
    Name = "quick-mcp-poc-ssm-kms-key"
  }
}

resource "aws_kms_alias" "ssm" {
  name          = "alias/quick-mcp-poc-ssm"
  target_key_id = aws_kms_key.ssm.key_id
}

# Non-sensitive configuration committed in plaintext and registered as String.
# To add: append { "/some/key" = { value = "...", description = "..." } }.
locals {
  ssm_plain_parameters = {
    "/quick-api/base" = {
      value       = "https://qr1.devmarket.myquick.net/home/member/wam_mxlgn/common/docs/api/"
      description = "QUICK API base URL"
    }
  }
}

# KMS-encrypted secrets committed as CiphertextBlob and registered as SecureString.
# payload = base64 CiphertextBlob produced by scripts/encrypt-secret.sh
# (i.e. `aws kms encrypt --key-id alias/quick-mcp-poc-ssm`).
locals {
  ssm_parameters = {
    "/quick-api/user" = {
      payload     = "AQICAHhGSAHA/GqHz1jXh5yNt6DjGv6Y08P/EXX97GMLxq4qVwFoZxA6BHsBq4qnaQdhB0dEAAAAaDBmBgkqhkiG9w0BBwagWTBXAgEAMFIGCSqGSIb3DQEHATAeBglghkgBZQMEAS4wEQQMSppyVa2TXfC8C97hAgEQgCUf0w4LeupehaiwD7sJoPyjtcU866+rfI04GtvMjVG4DZW+TjhV"
      description = "QUICK API basic auth user"
    }
    "/quick-api/pass" = {
      payload     = "AQICAHhGSAHA/GqHz1jXh5yNt6DjGv6Y08P/EXX97GMLxq4qVwHqqslfeAoS2tdSGCgzlUvEAAAAZjBkBgkqhkiG9w0BBwagVzBVAgEAMFAGCSqGSIb3DQEHATAeBglghkgBZQMEAS4wEQQMXi741XbHYsAeZqd2AgEQgCMBLfZxRcy8AP/VCki+VEIa/+vCPoPHCQaUC+Dcvs0daMJRRA=="
      description = "QUICK API basic auth password"
    }
  }
}

resource "aws_ssm_parameter" "ssm_plain_parameters" {
  for_each = local.ssm_plain_parameters

  name        = "/quick-mcp-poc${each.key}"
  type        = "String"
  value       = each.value.value
  description = each.value.description
}

# Entries with an empty payload are treated as placeholders and skipped.
# Once a CiphertextBlob is filled in they are registered as SecureString.
data "aws_kms_secrets" "ssm_parameters" {
  for_each = { for k, v in local.ssm_parameters : k => v if v.payload != "" }
  secret {
    name    = each.key
    payload = each.value.payload
  }
}

resource "aws_ssm_parameter" "ssm_parameters" {
  for_each = { for k, v in local.ssm_parameters : k => v if v.payload != "" }

  name        = "/quick-mcp-poc${each.key}"
  type        = "SecureString"
  key_id      = aws_kms_key.ssm.id
  value       = data.aws_kms_secrets.ssm_parameters[each.key].plaintext[each.key]
  description = each.value.description
}

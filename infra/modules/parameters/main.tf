terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.24"
    }
  }
}

locals {
  name_base = "${var.name_prefix}${var.resource_suffix}"
}

resource "aws_kms_key" "ssm" {
  description         = "KMS key for SSM Parameter Store in ${local.name_base}"
  enable_key_rotation = true

  tags = merge(var.tags, {
    Name = "${local.name_base}-ssm-kms-key"
  })
}

resource "aws_kms_alias" "ssm" {
  name          = var.kms_alias_name
  target_key_id = aws_kms_key.ssm.key_id
}

# Non-sensitive configuration committed in plaintext and registered as String.
# To add: append { "/some/key" = { value = "...", description = "..." } }.
resource "aws_ssm_parameter" "ssm_plain_parameters" {
  for_each = var.plain_parameters

  name        = "${var.ssm_path_prefix}${each.key}"
  type        = "String"
  value       = each.value.value
  description = each.value.description

  tags = var.tags
}

# KMS-encrypted secrets committed as CiphertextBlob and registered as SecureString.
# payload = base64 CiphertextBlob produced by scripts/encrypt-secret.sh
# (i.e. `aws kms encrypt --key-id alias/quick-mcp-poc-ssm`).
#
# Entries with an empty payload are treated as placeholders and skipped.
# Once a CiphertextBlob is filled in they are registered as SecureString.
#
# この payload != "" ガードは納品先での二段階適用を成立させる要であり、
# 削ってはならない。復号に使う KMS キーは同じ apply で作られるため、
# 初回は暗号文を入れられない (DELIVERY-BLOCKERS DB-04)。
data "aws_kms_secrets" "ssm_parameters" {
  for_each = { for k, v in var.encrypted_parameters : k => v if v.payload != "" }

  secret {
    name    = each.key
    payload = each.value.payload
  }
}

resource "aws_ssm_parameter" "ssm_parameters" {
  for_each = { for k, v in var.encrypted_parameters : k => v if v.payload != "" }

  name        = "${var.ssm_path_prefix}${each.key}"
  type        = "SecureString"
  key_id      = aws_kms_key.ssm.id
  value       = data.aws_kms_secrets.ssm_parameters[each.key].plaintext[each.key]
  description = each.value.description

  tags = var.tags
}

# 平文で受け取り SecureString として登録する。playground のプレースホルダ用。
# 実 credential をここへ流さないこと。値は state に平文で残る。
resource "aws_ssm_parameter" "ssm_plaintext_parameters" {
  for_each = var.plaintext_parameters

  name   = "${var.ssm_path_prefix}${each.key}"
  type   = "SecureString"
  key_id = aws_kms_key.ssm.id
  # キーは for_each に使うため変数全体を sensitive にできない。値だけをここで
  # マークし、plan 出力に平文が出ないようにする。
  value       = sensitive(each.value.value)
  description = each.value.description

  tags = var.tags
}

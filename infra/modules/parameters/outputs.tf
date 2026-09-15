output "kms_key_arn" {
  description = "SSM 暗号化用 KMS キーの ARN。ECS タスク実行ロールの kms:Decrypt 許可に渡す。"
  value       = aws_kms_key.ssm.arn
}

output "kms_key_id" {
  description = "同キーの ID。aws_ssm_parameter の key_id に渡す形式。"
  value       = aws_kms_key.ssm.id
}

output "kms_alias_name" {
  description = "KMS エイリアス名。環境ルートの ssm_kms_key_alias 出力に渡す。"
  value       = aws_kms_alias.ssm.name
}

output "ssm_path_prefix" {
  description = "SSM パラメータのパスプレフィックス。ecspresso が読む ssm_prefix 出力の元。"
  value       = var.ssm_path_prefix
}

output "parameter_arn_pattern" {
  description = "このモジュールが作るパラメータ全体を指す ARN パターン。IAM ポリシーに使う。"
  value       = "${var.ssm_path_prefix}/*"
}

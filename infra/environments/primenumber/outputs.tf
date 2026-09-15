# 移行元 terraform-playground-pattern4/outputs.tf:1-56 の 14 出力を、
# 名前をそのままに再現している。
#
# このうち 8 つは ecspresso との互換契約である。
# ecspresso/app/ecs-task-def.json と ecs-service-def.json が tfstate プラグイン
# 経由で名前で読んでおり、改名すると Terraform エラーではなく、デプロイ時に
# 難解な ecspresso テンプレートエラーとして初めて露見する (docs/23 §3.3)。
#
#   ecr_repository_url / ecs_cloudwatch_log_group_name / ecs_task_execution_role_arn
#   ecs_app_task_role_arn / ecs_security_group_id / ecs_private_subnet_ids
#   alb_target_group_arn / ssm_prefix

output "ecr_repository_url" {
  value = module.mcp_server_ecs.ecr_repository_url
}

output "ecs_cloudwatch_log_group_name" {
  value = module.mcp_server_ecs.log_group_name
}

output "ecs_task_execution_role_arn" {
  value = module.mcp_server_ecs.task_execution_role_arn
}

output "ecs_app_task_role_arn" {
  value = module.mcp_server_ecs.app_task_role_arn
}

output "ecs_security_group_id" {
  value = module.mcp_server_ecs.ecs_security_group_id
}

output "ecs_private_subnet_ids" {
  value = module.network.private_subnet_ids_list
}

output "alb_target_group_arn" {
  value = module.mcp_server_ecs.target_group_arn
}

output "cognito_user_pool_id" {
  value = module.auth.user_pool_id
}

output "cognito_user_pool_client_id" {
  value = module.auth.user_pool_client_id
}

output "api_gateway_endpoint" {
  value = module.api_gateway.api_endpoint
}

output "cognito_host" {
  value = module.auth.cognito_hosted_ui_base_url
}

# moved 適用前に、この出力の値が terraform.tfvars の
# resource_server_identifier と完全一致することを確認すること。
# 1 文字違えば resource server が destroy/create され、発行済み DCR
# クライアントのスコープ付与が全滅する (docs/23 §1.2)。
output "cognito_resource_server_identifier" {
  value = module.auth.resource_server_identifier
}

output "ssm_prefix" {
  value = module.parameters.ssm_path_prefix
}

output "ssm_kms_key_alias" {
  value = module.parameters.kms_alias_name
}

# --- 移行元には無いが運用上あると助かるもの ---

output "cloudfront_domain" {
  description = "CloudFront ディストリビューションのドメイン。MCP クライアントの接続先。"
  value       = module.edge_waf.cloudfront_domain
}

output "waf_web_acl_arn" {
  value = module.edge_waf.web_acl_arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecs_cloudwatch_log_group_name" {
  value = aws_cloudwatch_log_group.ecs.name
}

output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "ecs_app_task_role_arn" {
  value = aws_iam_role.ecs_app_task.arn
}

output "ecs_security_group_id" {
  value = aws_security_group.ecs.id
}

output "ecs_private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

output "alb_target_group_arn" {
  value = aws_lb_target_group.app.arn
}


output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.mcp.id
}

output "api_gateway_endpoint" {
  value = aws_apigatewayv2_api.main.api_endpoint
}

output "cognito_host" {
  value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.ap-northeast-1.amazoncognito.com"
}

output "cognito_resource_server_identifier" {
  value = aws_cognito_resource_server.mcp.identifier
}

output "ssm_prefix" {
  value = "/quick-mcp-poc"
}

output "ssm_kms_key_alias" {
  value = aws_kms_alias.ssm.name
}

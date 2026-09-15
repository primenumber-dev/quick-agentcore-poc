# 自動生成: python3 infra/scripts/generate-moved.py
#
# terraform-playground-pattern4/ のフラットな state を、モジュール構成の
# アドレスへ移す。terraform state mv ではなく moved ブロックを使う理由は、
# diff でレビューでき、冪等で、apply 前に plan が検証してくれるため。
#
# 受け入れ基準: plan が 0 to add, 0 to change, 0 to destroy になること。
# 例外は aws_api_gateway_deployment.metadata の 1 件のみ(openapi.yaml が
# モジュール配下へ移り path.module が変わるため sha1 トリガが動く)。
# aws_cloudfront_distribution.edge に -/+ が出たら即中断すること。
#
# 詳細: docs/23-weekly-verification-plan-week6.md §4
#
# 据え置き(moved ブロックを書かない): random_password.origin_verify, aws_dynamodb_table.mcp_users

# --- network ---
moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}
moved {
  from = aws_subnet.public
  to   = module.network.aws_subnet.public
}
moved {
  from = aws_subnet.private
  to   = module.network.aws_subnet.private
}
moved {
  from = aws_internet_gateway.main
  to   = module.network.aws_internet_gateway.main
}
moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}
moved {
  from = aws_route_table.private
  to   = module.network.aws_route_table.private
}
moved {
  from = aws_route_table_association.public
  to   = module.network.aws_route_table_association.public
}
moved {
  from = aws_route_table_association.private
  to   = module.network.aws_route_table_association.private
}
moved {
  from = aws_eip.nat
  to   = module.network.aws_eip.nat
}
moved {
  from = aws_instance.nat
  to   = module.network.aws_instance.nat
}
moved {
  from = aws_security_group.nat
  to   = module.network.aws_security_group.nat
}

# --- parameters ---
moved {
  from = aws_kms_key.ssm
  to   = module.parameters.aws_kms_key.ssm
}
moved {
  from = aws_kms_alias.ssm
  to   = module.parameters.aws_kms_alias.ssm
}

# --- mcp_server_ecs ---
moved {
  from = aws_ecs_cluster.main
  to   = module.mcp_server_ecs.aws_ecs_cluster.main
}
moved {
  from = aws_cloudwatch_log_group.ecs
  to   = module.mcp_server_ecs.aws_cloudwatch_log_group.ecs
}
moved {
  from = aws_iam_role.ecs_app_task
  to   = module.mcp_server_ecs.aws_iam_role.ecs_app_task
}
moved {
  from = aws_iam_role.ecs_task_execution
  to   = module.mcp_server_ecs.aws_iam_role.ecs_task_execution
}
moved {
  from = aws_iam_role_policy.ecs_app_task_dynamodb
  to   = module.mcp_server_ecs.aws_iam_role_policy.ecs_app_task_dynamodb
}
moved {
  from = aws_iam_role_policy.ecs_app_task_ssm
  to   = module.mcp_server_ecs.aws_iam_role_policy.ecs_app_task_ssm
}
moved {
  from = aws_iam_role_policy.ecs_task_execution_ssm
  to   = module.mcp_server_ecs.aws_iam_role_policy.ecs_task_execution_ssm
}
moved {
  from = aws_iam_role_policy_attachment.ecs_task_execution
  to   = module.mcp_server_ecs.aws_iam_role_policy_attachment.ecs_task_execution
}
moved {
  from = aws_lb.main
  to   = module.mcp_server_ecs.aws_lb.main
}
moved {
  from = aws_lb_listener.http
  to   = module.mcp_server_ecs.aws_lb_listener.http
}
moved {
  from = aws_lb_target_group.app
  to   = module.mcp_server_ecs.aws_lb_target_group.app
}
moved {
  from = aws_security_group.alb
  to   = module.mcp_server_ecs.aws_security_group.alb
}
moved {
  from = aws_security_group.ecs
  to   = module.mcp_server_ecs.aws_security_group.ecs
}
moved {
  from = aws_ecr_repository.app
  to   = module.mcp_server_ecs.aws_ecr_repository.app
}
moved {
  from = aws_ecr_lifecycle_policy.app
  to   = module.mcp_server_ecs.aws_ecr_lifecycle_policy.app
}

# --- auth ---
moved {
  from = aws_cognito_user_pool.main
  to   = module.auth.aws_cognito_user_pool.main
}
moved {
  from = aws_cognito_user_pool_client.mcp
  to   = module.auth.aws_cognito_user_pool_client.mcp
}
moved {
  from = aws_cognito_user_pool_domain.main
  to   = module.auth.aws_cognito_user_pool_domain.main
}
moved {
  from = aws_cognito_resource_server.mcp
  to   = module.auth.aws_cognito_resource_server.mcp
}
moved {
  from = aws_cognito_managed_login_branding.main
  to   = module.auth.aws_cognito_managed_login_branding.main
}

# --- dcr ---
moved {
  from = aws_lambda_function.dcr_authorizer
  to   = module.dcr.aws_lambda_function.dcr_authorizer
}
moved {
  from = aws_lambda_function.dcr_register
  to   = module.dcr.aws_lambda_function.dcr_register
}
moved {
  from = aws_iam_role.dcr_authorizer
  to   = module.dcr.aws_iam_role.dcr_authorizer
}
moved {
  from = aws_iam_role.dcr_register
  to   = module.dcr.aws_iam_role.dcr_register
}
moved {
  from = aws_iam_role_policy.dcr_authorizer_dynamodb
  to   = module.dcr.aws_iam_role_policy.dcr_authorizer_dynamodb
}
moved {
  from = aws_iam_role_policy.dcr_register_cognito
  to   = module.dcr.aws_iam_role_policy.dcr_register_cognito
}
moved {
  from = aws_iam_role_policy.dcr_register_dynamodb
  to   = module.dcr.aws_iam_role_policy.dcr_register_dynamodb
}
moved {
  from = aws_iam_role_policy_attachment.dcr_authorizer_basic
  to   = module.dcr.aws_iam_role_policy_attachment.dcr_authorizer_basic
}
moved {
  from = aws_iam_role_policy_attachment.dcr_register_basic
  to   = module.dcr.aws_iam_role_policy_attachment.dcr_register_basic
}
moved {
  from = aws_cloudwatch_log_group.dcr_authorizer
  to   = module.dcr.aws_cloudwatch_log_group.dcr_authorizer
}
moved {
  from = aws_cloudwatch_log_group.dcr_register
  to   = module.dcr.aws_cloudwatch_log_group.dcr_register
}

# --- api_gateway ---
moved {
  from = aws_apigatewayv2_api.main
  to   = module.api_gateway.aws_apigatewayv2_api.main
}
moved {
  from = aws_apigatewayv2_authorizer.lambda
  to   = module.api_gateway.aws_apigatewayv2_authorizer.lambda
}
moved {
  from = aws_apigatewayv2_integration.alb
  to   = module.api_gateway.aws_apigatewayv2_integration.alb
}
moved {
  from = aws_apigatewayv2_integration.cognito_authorize
  to   = module.api_gateway.aws_apigatewayv2_integration.cognito_authorize
}
moved {
  from = aws_apigatewayv2_integration.cognito_revoke
  to   = module.api_gateway.aws_apigatewayv2_integration.cognito_revoke
}
moved {
  from = aws_apigatewayv2_integration.cognito_token
  to   = module.api_gateway.aws_apigatewayv2_integration.cognito_token
}
moved {
  from = aws_apigatewayv2_integration.dcr_register
  to   = module.api_gateway.aws_apigatewayv2_integration.dcr_register
}
moved {
  from = aws_apigatewayv2_integration.metadata
  to   = module.api_gateway.aws_apigatewayv2_integration.metadata
}
moved {
  from = aws_apigatewayv2_route.authorize
  to   = module.api_gateway.aws_apigatewayv2_route.authorize
}
moved {
  from = aws_apigatewayv2_route.mcp
  to   = module.api_gateway.aws_apigatewayv2_route.mcp
}
moved {
  from = aws_apigatewayv2_route.register
  to   = module.api_gateway.aws_apigatewayv2_route.register
}
moved {
  from = aws_apigatewayv2_route.revoke
  to   = module.api_gateway.aws_apigatewayv2_route.revoke
}
moved {
  from = aws_apigatewayv2_route.token
  to   = module.api_gateway.aws_apigatewayv2_route.token
}
moved {
  from = aws_apigatewayv2_route.well_known
  to   = module.api_gateway.aws_apigatewayv2_route.well_known
}
moved {
  from = aws_apigatewayv2_stage.main
  to   = module.api_gateway.aws_apigatewayv2_stage.main
}
moved {
  from = aws_apigatewayv2_vpc_link.main
  to   = module.api_gateway.aws_apigatewayv2_vpc_link.main
}
moved {
  from = aws_api_gateway_rest_api.metadata
  to   = module.api_gateway.aws_api_gateway_rest_api.metadata
}
moved {
  from = aws_api_gateway_deployment.metadata
  to   = module.api_gateway.aws_api_gateway_deployment.metadata
}
moved {
  from = aws_api_gateway_stage.metadata
  to   = module.api_gateway.aws_api_gateway_stage.metadata
}
moved {
  from = aws_cloudwatch_log_group.apigw_access
  to   = module.api_gateway.aws_cloudwatch_log_group.apigw_access
}
moved {
  from = aws_lambda_permission.dcr_authorizer_invoke
  to   = module.api_gateway.aws_lambda_permission.dcr_authorizer_invoke
}
moved {
  from = aws_lambda_permission.dcr_register_invoke
  to   = module.api_gateway.aws_lambda_permission.dcr_register_invoke
}

# --- edge_waf ---
moved {
  from = aws_cloudfront_distribution.edge
  to   = module.edge_waf.aws_cloudfront_distribution.edge
}
moved {
  from = aws_wafv2_web_acl.edge
  to   = module.edge_waf.aws_wafv2_web_acl.edge
}
moved {
  from = aws_wafv2_web_acl_logging_configuration.edge
  to   = module.edge_waf.aws_wafv2_web_acl_logging_configuration.edge
}
moved {
  from = aws_cloudwatch_log_group.waf_edge
  to   = module.edge_waf.aws_cloudwatch_log_group.waf_edge
}

# --- アドレスの形が変わるもの (for_each 化) ---
moved {
  from = aws_ssm_parameter.quick_api_base
  to   = module.parameters.aws_ssm_parameter.ssm_plain_parameters["/quick-api/base"]
}
moved {
  from = aws_ssm_parameter.quick_api_user
  to   = module.parameters.aws_ssm_parameter.ssm_plaintext_parameters["/quick-api/user"]
}
moved {
  from = aws_ssm_parameter.quick_api_pass
  to   = module.parameters.aws_ssm_parameter.ssm_plaintext_parameters["/quick-api/pass"]
}

output "user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "CognitoユーザープールID(旧ルート output cognito_user_pool_id 相当)。"
}

output "user_pool_arn" {
  value       = aws_cognito_user_pool.main.arn
  description = "CognitoユーザープールARN。DCR register Lambda の IAM ポリシーが参照する。"
}

output "user_pool_client_id" {
  value       = aws_cognito_user_pool_client.mcp.id
  description = "MCPアプリクライアントID(旧ルート output cognito_user_pool_client_id 相当)。"
}

output "domain" {
  value       = aws_cognito_user_pool_domain.main.domain
  description = "Hosted UI のドメインプレフィックス。"
}

output "cognito_hosted_ui_base_url" {
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
  description = "Hosted UI のベースURL。旧ルート output cognito_host(outputs.tf:42-44、リージョンは直書きだった)の再現。"
}

output "issuer_url" {
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  description = "Cognito の issuer URL。apigateway.tf:4-5 の local.cognito_issuer の再現で、jwks_uri の組み立てに使う。"
}

output "resource_server_identifier" {
  value       = aws_cognito_resource_server.mcp.identifier
  description = "resource server の identifier を実リソースから読み戻したもの(入力のパススルー)。旧ルート output cognito_resource_server_identifier(outputs.tf:46-48)との互換用。"
}

output "invoke_scope" {
  value       = "${aws_cognito_resource_server.mcp.identifier}/invoke"
  description = "DCR Authorizer が要求する完全修飾スコープ(lambda.tf:71 の REQUIRED_SCOPE)。"
}

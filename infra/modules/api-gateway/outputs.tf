output "api_id" {
  value       = aws_apigatewayv2_api.main.id
  description = "HTTP API の ID。"
}

output "api_endpoint" {
  value       = aws_apigatewayv2_api.main.api_endpoint
  description = "HTTP API の execute-api エンドポイント。cognito の resource server identifier と edge-waf のオリジンホストの導出元(outputs.tf:39、cloudfront_waf.tf:45)。"
}

output "api_execution_arn" {
  value       = aws_apigatewayv2_api.main.execution_arn
  description = "HTTP API の execution ARN。Lambda 実行許可の source_arn に使う(lambda.tf:94,181)。"
}

output "metadata_rest_api_id" {
  value       = aws_api_gateway_rest_api.metadata.id
  description = "メタデータ用 REST API の ID。"
}

output "stage_name" {
  value       = aws_apigatewayv2_stage.main.name
  description = "HTTP API のステージ名($default)。"
}

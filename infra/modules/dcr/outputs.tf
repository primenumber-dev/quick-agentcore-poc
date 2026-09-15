output "authorizer_function_name" {
  value       = aws_lambda_function.dcr_authorizer.function_name
  description = "Authorizer Lambda の関数名。api-gateway モジュールへ移した aws_lambda_permission.dcr_authorizer_invoke が使う。"
}

output "authorizer_invoke_arn" {
  value       = aws_lambda_function.dcr_authorizer.invoke_arn
  description = "Authorizer Lambda の invoke ARN。API Gateway の REQUEST型 Authorizer が参照する(apigateway.tf:97)。"
}

output "register_function_name" {
  value       = aws_lambda_function.dcr_register.function_name
  description = "Register Lambda の関数名。api-gateway モジュールへ移した aws_lambda_permission.dcr_register_invoke が使う。"
}

output "register_invoke_arn" {
  value       = aws_lambda_function.dcr_register.invoke_arn
  description = "Register Lambda の invoke ARN。POST /register の統合が参照する(apigateway.tf:80)。"
}

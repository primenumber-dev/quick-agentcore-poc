# OAuth 発見メタデータ(RFC 8414 / RFC 9728)。docs/19 §2.4-a の方針で、issuer は API Gateway ファサード、
# jwks_uri は Cognito、scopes_supported には Authorizer が要求する invoke スコープを含める。
locals {
  cognito_issuer = "https://cognito-idp.ap-northeast-1.amazonaws.com/${aws_cognito_user_pool.main.id}"
  as_metadata = {
    issuer                                = aws_apigatewayv2_api.main.api_endpoint
    authorization_endpoint                = "${aws_apigatewayv2_api.main.api_endpoint}/authorize"
    token_endpoint                        = "${aws_apigatewayv2_api.main.api_endpoint}/token"
    registration_endpoint                 = "${aws_apigatewayv2_api.main.api_endpoint}/register"
    revocation_endpoint                   = "${aws_apigatewayv2_api.main.api_endpoint}/revoke"
    jwks_uri                              = "${local.cognito_issuer}/.well-known/jwks.json"
    response_types_supported              = ["code"]
    response_modes_supported              = ["query"]
    code_challenge_methods_supported      = ["S256"]
    token_endpoint_auth_methods_supported = ["none", "client_secret_basic", "client_secret_post"]
    grant_types_supported                 = ["authorization_code", "refresh_token", "client_credentials"]
    scopes_supported                      = ["openid", "email", "profile", "${aws_cognito_resource_server.mcp.identifier}/invoke"]
    subject_types_supported               = ["public"]
    id_token_signing_alg_values_supported = ["RS256"]
    service_documentation                 = "https://github.com/primenumber-dev/quick-agentcore-poc"
  }
  metadata_openapi = templatefile("${path.module}/openapi.yaml", {
    API_GW_FRONT_BASE_URL      = aws_apigatewayv2_api.main.api_endpoint
    RESOURCE_SERVER_IDENTIFIER = aws_cognito_resource_server.mcp.identifier
    AS_METADATA_JSON           = jsonencode(local.as_metadata)
  })
}

resource "aws_api_gateway_rest_api" "metadata" {
  name = "quick-mcp-poc-metadata"

  body = local.metadata_openapi

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_deployment" "metadata" {
  rest_api_id = aws_api_gateway_rest_api.metadata.id

  triggers = {
    redeployment = sha1(local.metadata_openapi)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "metadata" {
  deployment_id = aws_api_gateway_deployment.metadata.id
  rest_api_id   = aws_api_gateway_rest_api.metadata.id
  stage_name    = "v1"
}

resource "aws_apigatewayv2_api" "main" {
  name          = "quick-mcp-poc"
  protocol_type = "HTTP"
}

# AUTHZ-04: 監査証跡。誰がいつ /register・/token・/mcp を叩き、Authorizer が何を理由に拒否したかを残す。
resource "aws_cloudwatch_log_group" "apigw_access" {
  name              = "/quick-mcp-poc/apigw-access"
  retention_in_days = 90
}

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw_access.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      requestTime      = "$context.requestTime"
      sourceIp         = "$context.identity.sourceIp"
      userAgent        = "$context.identity.userAgent"
      routeKey         = "$context.routeKey"
      method           = "$context.httpMethod"
      path             = "$context.path"
      status           = "$context.status"
      responseLatency  = "$context.responseLatency"
      integrationError = "$context.integrationErrorMessage"
      authorizerError  = "$context.authorizer.error"
      authorizerSub    = "$context.authorizer.sub"
      authorizerClient = "$context.authorizer.clientId"
      wafTestId        = "$context.requestHeader.X-Waf-Test-Id"
    })
  }

  # DCR実装(docs/08 §2.4)の乱用対策: 未認証の/registerだけ低いレートに絞る。
  route_settings {
    route_key              = "POST /register"
    throttling_burst_limit = 5
    throttling_rate_limit  = 2
  }
}

resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "quick-mcp-poc"
  security_group_ids = [aws_security_group.alb.id]
  subnet_ids         = [for s in aws_subnet.private : s.id]
}

resource "aws_apigatewayv2_integration" "metadata" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "GET"
  integration_uri    = "https://${aws_api_gateway_rest_api.metadata.id}.execute-api.ap-northeast-1.amazonaws.com/${aws_api_gateway_stage.metadata.stage_name}/.well-known/{proxy}"
}

resource "aws_apigatewayv2_integration" "cognito_authorize" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "GET"
  integration_uri    = "https://${aws_cognito_user_pool_domain.main.domain}.auth.ap-northeast-1.amazoncognito.com/oauth2/authorize"
}

resource "aws_apigatewayv2_integration" "cognito_token" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "POST"
  integration_uri    = "https://${aws_cognito_user_pool_domain.main.domain}.auth.ap-northeast-1.amazoncognito.com/oauth2/token"
}

# 8414-08: revocation_endpoint。Cognito の /oauth2/revoke へプロキシする。
resource "aws_apigatewayv2_integration" "cognito_revoke" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "POST"
  integration_uri    = "https://${aws_cognito_user_pool_domain.main.domain}.auth.ap-northeast-1.amazoncognito.com/oauth2/revoke"
}

resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = aws_lb_listener.http.arn
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  request_parameters = {
    # DCR実装(docs/08 §2.1)でJWT型AuthorizerからLambda Authorizerに置き換えたため、
    # 検証済みsubの参照元も $context.authorizer.jwt.claims.sub から
    # Lambdaのsimple response context($context.authorizer.<key>)に変更。
    "overwrite:header.x-cognito-sub" = "$context.authorizer.sub"
  }
}

resource "aws_apigatewayv2_integration" "dcr_register" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dcr_register.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_authorizer" "lambda" {
  api_id                            = aws_apigatewayv2_api.main.id
  authorizer_type                   = "REQUEST"
  name                               = "dcr-jwt-authorizer"
  authorizer_uri                    = aws_lambda_function.dcr_authorizer.invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
  # セキュリティレビュー(2026-09-02): 300秒キャッシュだと`cli delete-client`による
  # 失効が最大5分遅延して反映されない問題があった。失効の即時性を優先し短縮する。
  authorizer_result_ttl_in_seconds  = 0
}

resource "aws_apigatewayv2_route" "well_known" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /.well-known/{proxy+}"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.metadata.id}"
}

resource "aws_apigatewayv2_route" "authorize" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /authorize"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.cognito_authorize.id}"
}

resource "aws_apigatewayv2_route" "token" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /token"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.cognito_token.id}"
}

resource "aws_apigatewayv2_route" "revoke" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /revoke"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.cognito_revoke.id}"
}

resource "aws_apigatewayv2_route" "mcp" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "ANY /{proxy+}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.lambda.id
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

resource "aws_apigatewayv2_route" "register" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /register"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.dcr_register.id}"
}

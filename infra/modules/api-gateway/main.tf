# OAuth 発見メタデータ(RFC 8414 / RFC 9728)。docs/19 §2.4-a の方針で、issuer は API Gateway ファサード、
# jwks_uri は Cognito、scopes_supported には Authorizer が要求する invoke スコープを含める。
locals {
  cognito_issuer = var.cognito_issuer_url
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
    scopes_supported                      = ["openid", "email", "profile", "${var.resource_server_identifier}/invoke"]
    subject_types_supported               = ["public"]
    id_token_signing_alg_values_supported = ["RS256"]
    service_documentation                 = var.service_documentation_url
  }
  metadata_openapi = templatefile("${path.module}/openapi.yaml", {
    API_GW_FRONT_BASE_URL      = aws_apigatewayv2_api.main.api_endpoint
    RESOURCE_SERVER_IDENTIFIER = var.resource_server_identifier
    AS_METADATA_JSON           = jsonencode(local.as_metadata)
  })
}

resource "aws_api_gateway_rest_api" "metadata" {
  name = coalesce(var.metadata_api_name, "${var.name_prefix}-metadata")

  body = local.metadata_openapi

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
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
  stage_name    = var.metadata_stage_name

  tags = var.tags
}

resource "aws_apigatewayv2_api" "main" {
  name          = var.api_name
  protocol_type = "HTTP"

  tags = var.tags
}

# AUTHZ-04: 監査証跡。誰がいつ /register・/token・/mcp を叩き、Authorizer が何を理由に拒否したかを残す。
# enable_dcr = false(旧世代・pre-DCR)では、そもそもアクセスログ設定が存在しなかったため作らない。
resource "aws_cloudwatch_log_group" "apigw_access" {
  count = var.enable_dcr ? 1 : 0

  name              = var.access_log_group_name
  retention_in_days = var.access_log_retention_days

  tags = var.tags
}

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  dynamic "access_log_settings" {
    for_each = var.enable_dcr ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.apigw_access[0].arn
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
  }

  # DCR実装(docs/08 §2.4)の乱用対策: 未認証の/registerだけ低いレートに絞る。
  dynamic "route_settings" {
    for_each = var.enable_dcr ? [1] : []
    content {
      route_key              = "POST /register"
      throttling_burst_limit = var.register_throttle.burst
      throttling_rate_limit  = var.register_throttle.rate
    }
  }

  tags = var.tags
}

resource "aws_apigatewayv2_vpc_link" "main" {
  # 実リソース名は API と同じ "quick-mcp-poc"。resource_suffix は付けない(既存stateと差分ゼロにするため)。
  name               = var.api_name
  security_group_ids = [var.alb_security_group_id]
  subnet_ids         = var.private_subnet_ids

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "metadata" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "GET"
  integration_uri    = "https://${aws_api_gateway_rest_api.metadata.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.metadata.stage_name}/.well-known/{proxy}"
}

resource "aws_apigatewayv2_integration" "cognito_authorize" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "GET"
  integration_uri    = "https://${var.cognito_domain}.auth.${var.region}.amazoncognito.com/oauth2/authorize"
}

resource "aws_apigatewayv2_integration" "cognito_token" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "POST"
  integration_uri    = "https://${var.cognito_domain}.auth.${var.region}.amazoncognito.com/oauth2/token"
}

# 8414-08: revocation_endpoint。Cognito の /oauth2/revoke へプロキシする。
resource "aws_apigatewayv2_integration" "cognito_revoke" {
  count = var.enable_dcr ? 1 : 0

  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "POST"
  integration_uri    = "https://${var.cognito_domain}.auth.${var.region}.amazoncognito.com/oauth2/revoke"
}

resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = var.alb_listener_arn
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  request_parameters = {
    # DCR実装(docs/08 §2.1)でJWT型AuthorizerからLambda Authorizerに置き換えたため、
    # 検証済みsubの参照元も $context.authorizer.jwt.claims.sub から
    # Lambdaのsimple response context($context.authorizer.<key>)に変更。
    "overwrite:header.x-cognito-sub" = var.enable_dcr ? "$context.authorizer.sub" : "$context.authorizer.jwt.claims.sub"
  }
}

resource "aws_apigatewayv2_integration" "dcr_register" {
  count = var.enable_dcr ? 1 : 0

  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.register_invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_authorizer" "lambda" {
  count = var.enable_dcr ? 1 : 0

  api_id                            = aws_apigatewayv2_api.main.id
  authorizer_type                   = "REQUEST"
  name                              = "dcr-jwt-authorizer"
  authorizer_uri                    = var.authorizer_invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
  # セキュリティレビュー(2026-09-02): 300秒キャッシュだと`cli delete-client`による
  # 失効が最大5分遅延して反映されない問題があった。失効の即時性を優先し短縮する。
  authorizer_result_ttl_in_seconds = var.authorizer_ttl_seconds
}

# enable_dcr = false: 旧世代(pre-DCR)の JWT Authorizer。terraform/apigateway.tf:84-99 と同形。
resource "aws_apigatewayv2_authorizer" "cognito" {
  count = var.enable_dcr ? 0 : 1

  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  name             = "cognito"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    # NOTE: aws_cognito_resource_server.mcp.identifier (the resource server
    # identifier) does not match the `aud`/`client_id` claim Cognito actually
    # puts in issued tokens, so this rejected every legitimate token with a
    # 401. Verified in a playground replica of this stack; see
    # docs/07-vpc-waf-cost-verification.md §2.4 for the reproduction.
    #
    # したがって audience には **アプリクライアントID** を渡すこと。
    # var.resource_server_identifier を渡してはならない(本番401バグの再発)。
    audience = [var.cognito_app_client_id]
    issuer   = var.cognito_issuer_url
  }
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
  count = var.enable_dcr ? 1 : 0

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /revoke"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.cognito_revoke[0].id}"
}

resource "aws_apigatewayv2_route" "mcp" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "ANY /{proxy+}"
  authorization_type = var.enable_dcr ? "CUSTOM" : "JWT"
  authorizer_id      = var.enable_dcr ? aws_apigatewayv2_authorizer.lambda[0].id : aws_apigatewayv2_authorizer.cognito[0].id
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

resource "aws_apigatewayv2_route" "register" {
  count = var.enable_dcr ? 1 : 0

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "POST /register"
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.dcr_register[0].id}"
}

# --- Lambda 実行許可 ---
# docs/23 §1.3: これらは API が **与える** 権限であるため lambda.tf(dcr モジュール)ではなく
# こちらに置く。dcr → api-gateway の依存を一方向に保つための配置である。

resource "aws_lambda_permission" "dcr_authorizer_invoke" {
  count = var.enable_dcr ? 1 : 0

  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.authorizer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/authorizers/*"
}

resource "aws_lambda_permission" "dcr_register_invoke" {
  count = var.enable_dcr ? 1 : 0

  statement_id  = "AllowAPIGatewayInvokeRegister"
  action        = "lambda:InvokeFunction"
  function_name = var.register_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/register"
}

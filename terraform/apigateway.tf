resource "aws_api_gateway_rest_api" "metadata" {
  name = "quick-mcp-poc-metadata"

  body = templatefile("${path.module}/openapi.yaml", {
    API_GW_FRONT_BASE_URL = aws_apigatewayv2_api.main.api_endpoint
  })

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_deployment" "metadata" {
  rest_api_id = aws_api_gateway_rest_api.metadata.id

  triggers = {
    redeployment = sha1(templatefile("${path.module}/openapi.yaml", {
      API_GW_FRONT_BASE_URL = aws_apigatewayv2_api.main.api_endpoint
    }))
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

resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
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

resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = aws_lb_listener.http.arn
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  request_parameters = {
    "overwrite:header.x-cognito-sub" = "$context.authorizer.jwt.claims.sub"
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
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
    audience = [aws_cognito_user_pool_client.mcp.id]
    issuer   = "https://cognito-idp.ap-northeast-1.amazonaws.com/${aws_cognito_user_pool.main.id}"
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

resource "aws_apigatewayv2_route" "mcp" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "ANY /{proxy+}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

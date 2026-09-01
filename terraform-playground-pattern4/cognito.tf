# 本番相当のterraform/cognito.tfから移植。ドメイン名のみ変更(quick-mcp-poc-authは
# 本番相当アカウントが既に使用中で、Cognitoドメインプレフィックスはリージョン内でグローバルに一意のため)。
# "local"開発用プールはこの検証では不要なため省略。

resource "aws_cognito_user_pool" "main" {
  name                = "quick-mcp-poc-pattern4-verify-users"
  username_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
  }

  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = {
    Name = "quick-mcp-poc-pattern4-verify-user-pool"
  }
}

resource "aws_cognito_user_pool_client" "mcp" {
  name         = "quick-mcp-poc-mcp-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  # invokeスコープを追加(セキュリティレビュー2026-09-02): Lambda Authorizerがスコープ検証を
  # 必須にしたため、このクライアントも要求できるようにする。実際に付与されるにはOAuth
  # フローのscopeパラメータにも含める必要がある(scripts/invoke_agentcore_mcp_jwt.py等参照)。
  allowed_oauth_scopes                 = ["openid", "email", "profile", "${aws_apigatewayv2_api.main.api_endpoint}/mcp/invoke"]
  supported_identity_providers         = ["COGNITO"]
  explicit_auth_flows                  = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  callback_urls = [
    "http://localhost:3030/callback",
  ]
}

resource "aws_cognito_resource_server" "mcp" {
  user_pool_id = aws_cognito_user_pool.main.id
  identifier   = "${aws_apigatewayv2_api.main.api_endpoint}/mcp"
  name         = "quick-mcp-poc-mcp"

  # DCR実装(docs/08-weekly-verification-plan.md §2)向けに追加。
  # 動的登録クライアントに付与する固定スコープ。
  scope {
    scope_name        = "invoke"
    scope_description = "Invoke MCP tools"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain                = "quick-mcp-poc-pattern4-verify"
  user_pool_id          = aws_cognito_user_pool.main.id
  managed_login_version = 2
}

resource "aws_cognito_managed_login_branding" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  client_id    = aws_cognito_user_pool_client.mcp.id
  settings     = local.managed_login_branding_settings
}

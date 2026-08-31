resource "aws_cognito_user_pool" "main" {
  name                = "quick-mcp-poc-users"
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
    Name = "quick-mcp-poc-user-pool"
  }
}

resource "aws_cognito_user_pool_client" "mcp" {
  name         = "quick-mcp-poc-mcp-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = [
    "https://claude.ai/api/mcp/auth_callback",
    "http://localhost:3000/callback",
  ]
}

resource "aws_cognito_resource_server" "mcp" {
  user_pool_id = aws_cognito_user_pool.main.id
  identifier   = "${aws_apigatewayv2_api.main.api_endpoint}/mcp"
  name         = "quick-mcp-poc-mcp"
}

resource "aws_cognito_user_pool_domain" "main" {
  domain                = "quick-mcp-poc-auth"
  user_pool_id          = aws_cognito_user_pool.main.id
  managed_login_version = 2
}

resource "aws_cognito_managed_login_branding" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  client_id    = aws_cognito_user_pool_client.mcp.id
  settings     = local.managed_login_branding_settings
}

# Local development pool

resource "aws_cognito_user_pool" "local" {
  name                = "local-quick-mcp-poc-users"
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
    Name = "local-quick-mcp-poc-user-pool"
  }
}

resource "aws_cognito_user_pool_client" "local" {
  name         = "local-quick-mcp-poc-mcp-client"
  user_pool_id = aws_cognito_user_pool.local.id

  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = [
    "http://localhost:3000/callback",
  ]
}

resource "aws_cognito_resource_server" "local" {
  user_pool_id = aws_cognito_user_pool.local.id
  identifier   = "http://localhost:8080/mcp"
  name         = "local-quick-mcp-poc-mcp"
}

resource "aws_cognito_user_pool_domain" "local" {
  domain                = "local-quick-mcp-poc-auth"
  user_pool_id          = aws_cognito_user_pool.local.id
  managed_login_version = 2
}

resource "aws_cognito_managed_login_branding" "local" {
  user_pool_id = aws_cognito_user_pool.local.id
  client_id    = aws_cognito_user_pool_client.local.id
  settings     = local.managed_login_branding_settings
}


# 本番相当のterraform/cognito.tfから移植。ドメイン名のみ変更(quick-mcp-poc-authは
# 本番相当アカウントが既に使用中で、Cognitoドメインプレフィックスはリージョン内でグローバルに一意のため)。
# "local"開発用プールは var.enable_local_pool で任意化している(既定は無効)。
#
# 移行元: terraform-playground-pattern4/cognito.tf + cognito_branding.tf
#         terraform/cognito.tf:59-116 ("local"プール)
#
# docs/23 §1.2: aws_cognito_resource_server.mcp の identifier は元々 API Gateway の
# api_endpoint から導出していたが、var.resource_server_identifier へ変数化した。
# これにより本モジュールから API Gateway リソースへの参照は完全に消えている。

locals {
  # cognito_branding.tf:1-130 の既定ブランディング設定。
  # var.branding_settings が指定された場合はそちらを優先する。
  default_managed_login_branding_settings = jsonencode({
    categories = {
      auth = {
        authMethodOrder = [[
          { display = "INPUT", type = "USERNAME_PASSWORD" }
        ]]
        federation = {
          interfaceStyle = "BUTTON_LIST"
          order          = []
        }
      }
      form = {
        displayGraphics     = true
        instructions        = { enabled = false }
        languageSelector    = { enabled = true }
        location            = { horizontal = "CENTER", vertical = "CENTER" }
        sessionTimerDisplay = "NONE"
      }
      global = {
        colorSchemeMode = "LIGHT"
        pageFooter      = { enabled = false }
        pageHeader      = { enabled = false }
        spacingDensity  = "REGULAR"
      }
      signUp = {
        acceptanceElements = [{ enforcement = "NONE", textKey = "en" }]
      }
    }
    componentClasses = {
      buttons = { borderRadius = 8.0 }
      divider = { lightMode = { borderColor = "d4d4d4ff" } }
      dropDown = {
        borderRadius = 8.0
        lightMode = {
          defaults = { itemBackgroundColor = "ffffffff" }
          hover    = { itemBackgroundColor = "f0f7f5ff", itemBorderColor = "0a7463ff", itemTextColor = "000716ff" }
          match    = { itemBackgroundColor = "e0eeebff", itemTextColor = "0a7463ff" }
        }
      }
      focusState = { lightMode = { borderColor = "0a7463ff" } }
      idpButtons = { icons = { enabled = true } }
      input = {
        borderRadius = 8.0
        lightMode = {
          defaults         = { backgroundColor = "ffffffff", borderColor = "7d8998ff" }
          placeholderColor = "5f6b7aff"
        }
      }
      inputDescription = { lightMode = { textColor = "5f6b7aff" } }
      inputLabel       = { lightMode = { textColor = "000716ff" } }
      link = {
        lightMode = {
          defaults = { textColor = "0a7463ff" }
          hover    = { textColor = "085e50ff" }
        }
      }
      optionControls = {
        lightMode = {
          defaults = { backgroundColor = "ffffffff", borderColor = "7d8998ff" }
          selected = { backgroundColor = "0a7463ff", foregroundColor = "ffffffff" }
        }
      }
      statusIndicator = {
        lightMode = {
          error   = { backgroundColor = "fff7f7ff", borderColor = "d91515ff", indicatorColor = "d91515ff" }
          pending = { indicatorColor = "aaaaaaaa" }
          success = { backgroundColor = "f2fcf3ff", borderColor = "037f0cff", indicatorColor = "037f0cff" }
          warning = { backgroundColor = "fffce9ff", borderColor = "8d6605ff", indicatorColor = "8d6605ff" }
        }
      }
    }
    components = {
      alert = {
        borderRadius = 12.0
        lightMode    = { error = { backgroundColor = "fff7f7ff", borderColor = "d91515ff" } }
      }
      favicon = { enabledTypes = ["ICO", "SVG"] }
      form = {
        backgroundImage = { enabled = false }
        borderRadius    = 8.0
        lightMode       = { backgroundColor = "ffffffff", borderColor = "c6c6cdff" }
        logo            = { enabled = false, formInclusion = "IN", location = "CENTER", position = "TOP" }
      }
      idpButton = {
        custom = {}
        standard = {
          lightMode = {
            active   = { backgroundColor = "e0eeebff", borderColor = "085e50ff", textColor = "085e50ff" }
            defaults = { backgroundColor = "ffffffff", borderColor = "424650ff", textColor = "424650ff" }
            hover    = { backgroundColor = "f0f7f5ff", borderColor = "085e50ff", textColor = "085e50ff" }
          }
        }
      }
      pageBackground = {
        image     = { enabled = false }
        lightMode = { color = "f5f5f5ff" }
      }
      pageFooter = {
        backgroundImage = { enabled = false }
        lightMode       = { background = { color = "fafafaff" }, borderColor = "d5dbdbff" }
        logo            = { enabled = false, location = "START" }
      }
      pageHeader = {
        backgroundImage = { enabled = false }
        lightMode       = { background = { color = "fafafaff" }, borderColor = "d5dbdbff" }
        logo            = { enabled = false, location = "START" }
      }
      pageText = {
        lightMode = { bodyColor = "414d5cff", descriptionColor = "414d5cff", headingColor = "000716ff" }
      }
      phoneNumberSelector = { displayType = "TEXT" }
      primaryButton = {
        lightMode = {
          active   = { backgroundColor = "085e50ff", textColor = "ffffffff" }
          defaults = { backgroundColor = "0a7463ff", textColor = "ffffffff" }
          disabled = { backgroundColor = "ffffffff", borderColor = "ffffffff" }
          hover    = { backgroundColor = "085e50ff", textColor = "ffffffff" }
        }
      }
      secondaryButton = {
        lightMode = {
          active   = { backgroundColor = "e0eeebff", borderColor = "085e50ff", textColor = "085e50ff" }
          defaults = { backgroundColor = "ffffffff", borderColor = "0a7463ff", textColor = "0a7463ff" }
          hover    = { backgroundColor = "f0f7f5ff", borderColor = "085e50ff", textColor = "085e50ff" }
        }
      }
    }
  })

  managed_login_branding_settings = (
    var.branding_settings != null
    ? var.branding_settings
    : local.default_managed_login_branding_settings
  )

  name_base = "${var.name_prefix}${var.resource_suffix}"
}

resource "aws_cognito_user_pool" "main" {
  name                = var.user_pool_name
  username_attributes = ["email"]

  password_policy {
    minimum_length    = var.password_policy.minimum_length
    require_uppercase = var.password_policy.require_uppercase
    require_lowercase = var.password_policy.require_lowercase
    require_numbers   = var.password_policy.require_numbers
    require_symbols   = var.password_policy.require_symbols
  }

  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = merge(var.tags, {
    Name = "${local.name_base}-user-pool"
  })
}

resource "aws_cognito_user_pool_client" "mcp" {
  # 移行元は suffix を含まない "quick-mcp-poc-mcp-client"(cognito.tf:29)
  name         = "${var.name_prefix}-mcp-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  # invokeスコープを追加(セキュリティレビュー2026-09-02): Lambda Authorizerがスコープ検証を
  # 必須にしたため、このクライアントも要求できるようにする。実際に付与されるにはOAuth
  # フローのscopeパラメータにも含める必要がある(scripts/invoke_agentcore_mcp_jwt.py等参照)。
  allowed_oauth_scopes         = concat(["openid", "email", "profile", "${var.resource_server_identifier}/invoke"], var.extra_oauth_scopes)
  supported_identity_providers = ["COGNITO"]
  explicit_auth_flows          = var.explicit_auth_flows

  callback_urls = var.callback_urls
}

resource "aws_cognito_resource_server" "mcp" {
  user_pool_id = aws_cognito_user_pool.main.id
  identifier   = var.resource_server_identifier
  name         = var.resource_server_name

  # DCR実装(docs/08-weekly-verification-plan.md §2)向けに追加。
  # 動的登録クライアントに付与する固定スコープ。
  scope {
    scope_name        = "invoke"
    scope_description = "Invoke MCP tools"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain                = var.domain_prefix
  user_pool_id          = aws_cognito_user_pool.main.id
  managed_login_version = 2
}

resource "aws_cognito_managed_login_branding" "main" {
  user_pool_id = aws_cognito_user_pool.main.id
  client_id    = aws_cognito_user_pool_client.mcp.id
  settings     = local.managed_login_branding_settings
}

# --- Local development pool (terraform/cognito.tf:59-116) ---
#
# docs/23 §1.4: 任意化は必ず「リソースの count」で行う。module ブロックに count /
# for_each / depends_on を付けるとモジュール全体が単一のグラフノードに潰れ、
# 存在しなかったはずの循環参照が発生する。

resource "aws_cognito_user_pool" "local" {
  count = var.enable_local_pool ? 1 : 0

  name                = "local-${var.name_prefix}-users"
  username_attributes = ["email"]

  password_policy {
    minimum_length    = var.password_policy.minimum_length
    require_uppercase = var.password_policy.require_uppercase
    require_lowercase = var.password_policy.require_lowercase
    require_numbers   = var.password_policy.require_numbers
    require_symbols   = var.password_policy.require_symbols
  }

  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = merge(var.tags, {
    Name = "local-${var.name_prefix}-user-pool"
  })
}

resource "aws_cognito_user_pool_client" "local" {
  count = var.enable_local_pool ? 1 : 0

  name         = "local-${var.name_prefix}-mcp-client"
  user_pool_id = aws_cognito_user_pool.local[0].id

  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = var.local_pool_callback_urls
}

resource "aws_cognito_resource_server" "local" {
  count = var.enable_local_pool ? 1 : 0

  user_pool_id = aws_cognito_user_pool.local[0].id
  identifier   = var.local_pool_resource_server_identifier
  name         = "local-${var.name_prefix}-mcp"
}

resource "aws_cognito_user_pool_domain" "local" {
  count = var.enable_local_pool ? 1 : 0

  domain                = var.local_pool_domain_prefix
  user_pool_id          = aws_cognito_user_pool.local[0].id
  managed_login_version = 2
}

resource "aws_cognito_managed_login_branding" "local" {
  count = var.enable_local_pool ? 1 : 0

  user_pool_id = aws_cognito_user_pool.local[0].id
  client_id    = aws_cognito_user_pool_client.local[0].id
  settings     = local.managed_login_branding_settings
}

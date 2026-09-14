# DCR実装(docs/08-weekly-verification-plan.md §2)。
# JWT型Authorizerは動的に増えるclient_idに対応できないため、Lambda(REQUEST型)Authorizerに置き換え、
# 併せてRFC 7591準拠のPOST /registerエンドポイントを追加する。

# DCR 台帳・テナント台帳のテーブル。terraform 管理外の既存テーブル(docs/19 §2.1 F12)。
# Lambda / server / cli の3コンポーネントと IAM で同じ名前を参照する。
locals {
  dcr_table_name = "quick-mcp-poc-users"
  dcr_table_arn  = "arn:aws:dynamodb:ap-northeast-1:883660531246:table/${local.dcr_table_name}"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "archive_file" "authorizer" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/dist/authorizer"
  output_path = "${path.module}/../lambda/dist/authorizer.zip"
}

data "archive_file" "register" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/dist/register"
  output_path = "${path.module}/../lambda/dist/register.zip"
}

# --- Authorizer Lambda ---

resource "aws_iam_role" "dcr_authorizer" {
  name               = "quick-mcp-poc-dcr-authorizer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dcr_authorizer_basic" {
  role       = aws_iam_role.dcr_authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "dcr_authorizer_dynamodb" {
  statement {
    actions   = ["dynamodb:GetItem"]
    resources = [local.dcr_table_arn]
  }
}

resource "aws_iam_role_policy" "dcr_authorizer_dynamodb" {
  name   = "quick-mcp-poc-dcr-authorizer-dynamodb"
  role   = aws_iam_role.dcr_authorizer.id
  policy = data.aws_iam_policy_document.dcr_authorizer_dynamodb.json
}

resource "aws_lambda_function" "dcr_authorizer" {
  function_name    = "quick-mcp-poc-dcr-authorizer"
  role             = aws_iam_role.dcr_authorizer.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256
  timeout          = 5

  environment {
    variables = {
      USER_POOL_ID               = aws_cognito_user_pool.main.id
      REQUIRED_SCOPE             = "${aws_cognito_resource_server.mcp.identifier}/invoke"
      RESOURCE_SERVER_IDENTIFIER = aws_cognito_resource_server.mcp.identifier
      TABLE_NAME                 = local.dcr_table_name
      # docs/19 §2.4-a: 401化の試行。"throw" で例外を投げたときの API Gateway の応答コードを観測する。
      DENY_MODE                        = "throw"
      REQUIRE_AUDIENCE_FOR_USER_TOKENS = "false"
      # WAF-03: CloudFront の秘密ヘッダ(cloudfront_waf.tf)。観測モード(false)から開始
      ORIGIN_VERIFY_SECRET  = random_password.origin_verify.result
      ENFORCE_ORIGIN_VERIFY = "false"
    }
  }
}

resource "aws_cloudwatch_log_group" "dcr_authorizer" {
  name              = "/aws/lambda/${aws_lambda_function.dcr_authorizer.function_name}"
  retention_in_days = 90
}

resource "aws_lambda_permission" "dcr_authorizer_invoke" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dcr_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/authorizers/*"
}

# --- Register Lambda ---

resource "aws_iam_role" "dcr_register" {
  name               = "quick-mcp-poc-dcr-register-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dcr_register_basic" {
  role       = aws_iam_role.dcr_register.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "dcr_register_cognito" {
  statement {
    actions = [
      "cognito-idp:CreateUserPoolClient",
      "cognito-idp:DeleteUserPoolClient",
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:UpdateUserPoolClient",
      # CL-03: DCR クライアントに Managed Login ブランディングを割り当てる(無いとログイン画面が出ない)
      "cognito-idp:CreateManagedLoginBranding",
      "cognito-idp:DeleteManagedLoginBranding",
      "cognito-idp:DescribeManagedLoginBrandingByClient",
    ]
    resources = [aws_cognito_user_pool.main.arn]
  }
}

resource "aws_iam_role_policy" "dcr_register_cognito" {
  name   = "quick-mcp-poc-dcr-register-cognito"
  role   = aws_iam_role.dcr_register.id
  policy = data.aws_iam_policy_document.dcr_register_cognito.json
}

data "aws_iam_policy_document" "dcr_register_dynamodb" {
  statement {
    # UpdateItem: 登録数上限(COUNTER#dcr)と IP 単位レート制限(RATE#)のカウンタ
    actions   = ["dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem"]
    resources = [local.dcr_table_arn]
  }
}

resource "aws_iam_role_policy" "dcr_register_dynamodb" {
  name   = "quick-mcp-poc-dcr-register-dynamodb"
  role   = aws_iam_role.dcr_register.id
  policy = data.aws_iam_policy_document.dcr_register_dynamodb.json
}

resource "aws_lambda_function" "dcr_register" {
  function_name    = "quick-mcp-poc-dcr-register"
  role             = aws_iam_role.dcr_register.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  filename         = data.archive_file.register.output_path
  source_code_hash = data.archive_file.register.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      USER_POOL_ID               = aws_cognito_user_pool.main.id
      RESOURCE_SERVER_IDENTIFIER = aws_cognito_resource_server.mcp.identifier
      TABLE_NAME                 = local.dcr_table_name
      # MVPのアローリスト(docs/08 §2.4)。運用中に広げられるよう環境変数化。
      ALLOWED_REDIRECT_HOSTS = "claude.ai,claude.com"
      # docs/19 §2.4-c/d: 既定値・上限は環境変数で運用調整できるようにする
      DEFAULT_TOKEN_ENDPOINT_AUTH_METHOD  = "none"
      MAX_DCR_CLIENTS                     = "200"
      MAX_REGISTRATIONS_PER_IP_PER_MINUTE = "5"
      ACCESS_TOKEN_VALIDITY_MINUTES       = "60"
      APPLY_MANAGED_LOGIN_BRANDING        = "true"
    }
  }
}

resource "aws_cloudwatch_log_group" "dcr_register" {
  name              = "/aws/lambda/${aws_lambda_function.dcr_register.function_name}"
  retention_in_days = 90
}

resource "aws_lambda_permission" "dcr_register_invoke" {
  statement_id  = "AllowAPIGatewayInvokeRegister"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dcr_register.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*/register"
}

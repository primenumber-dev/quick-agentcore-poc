# DCR実装(docs/08-weekly-verification-plan.md §2)。
# JWT型Authorizerは動的に増えるclient_idに対応できないため、Lambda(REQUEST型)Authorizerに置き換え、
# 併せてRFC 7591準拠のPOST /registerエンドポイントを追加する。

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
    resources = ["arn:aws:dynamodb:ap-northeast-1:883660531246:table/quick-mcp-poc-users"]
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
      USER_POOL_ID   = aws_cognito_user_pool.main.id
      REQUIRED_SCOPE = "${aws_cognito_resource_server.mcp.identifier}/invoke"
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
    actions   = ["dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:ap-northeast-1:883660531246:table/quick-mcp-poc-users"]
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
      USER_POOL_ID              = aws_cognito_user_pool.main.id
      RESOURCE_SERVER_IDENTIFIER = aws_cognito_resource_server.mcp.identifier
      # MVPのアローリスト(docs/08 §2.4)。運用中に広げられるよう環境変数化。
      ALLOWED_REDIRECT_HOSTS = "claude.ai,claude.com"
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

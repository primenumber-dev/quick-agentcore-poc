# DCR実装(docs/08-weekly-verification-plan.md §2)。
# JWT型Authorizerは動的に増えるclient_idに対応できないため、Lambda(REQUEST型)Authorizerに置き換え、
# 併せてRFC 7591準拠のPOST /registerエンドポイントを追加する。
#
# 移行元: terraform-playground-pattern4/lambda.tf
#
# 移行にあたっての変更点(docs/23 §1.3):
#   1. aws_lambda_permission 2件(lambda.tf:89-95 / :176-182)は **api-gateway モジュールへ移した**。
#      両者は aws_apigatewayv2_api.main.execution_arn を参照するため、ここに残すと
#      dcr ⇄ api-gateway のレビュー不能な相互参照になる。権限は「APIが与えるもの」であり
#      api-gateway 側が置き場所として正しい。
#   2. random_password.origin_verify(cloudfront_waf.tf:48)は **環境ルートへ引き上げた**。
#      dcr と edge-waf の双方が参照するため、どちらかのモジュールに置くと
#      edge-waf → dcr → api-gateway → edge-waf の循環ができる。
#      ここでは var.origin_verify_secret として受け取る。
#   3. DCR台帳テーブル(locals.dcr_table_name / dcr_table_arn、lambda.tf:8-9)は入力に変更。
#      ARNにアカウントID 883660531246 が直書きされていたため、環境ルートで
#      region + account_id + table_name から組み立てて渡す。

# DCR 台帳・テナント台帳のテーブル。terraform 管理外の既存テーブル(docs/19 §2.1 F12)。
# Lambda / server / cli の3コンポーネントと IAM で同じ名前を参照する。

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
  source_dir  = "${var.lambda_source_dir}/dist/authorizer"
  output_path = "${var.lambda_source_dir}/dist/authorizer.zip"
}

data "archive_file" "register" {
  type        = "zip"
  source_dir  = "${var.lambda_source_dir}/dist/register"
  output_path = "${var.lambda_source_dir}/dist/register.zip"
}

locals {
  # 重要: 移行元 lambda.tf の名前は suffix を **含まない**("quick-mcp-poc-dcr-authorizer" 等、
  # lambda.tf:37,54,60,100,126,140,146)。playground の resource_suffix は "-pattern4-verify" だが、
  # ここで付けてしまうと全Lambda・全IAMロールが再作成され、docs/23 §4 の受け入れ基準
  # (0 to add, 0 to change, 0 to destroy)を満たさなくなる。よって name_prefix のみを使う。
  # var.resource_suffix はインタフェース統一のために受け取るが、名前には使わない。
  name_base = var.name_prefix
}

# --- Authorizer Lambda ---

resource "aws_iam_role" "dcr_authorizer" {
  name               = "${local.name_base}-dcr-authorizer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dcr_authorizer_basic" {
  role       = aws_iam_role.dcr_authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "dcr_authorizer_dynamodb" {
  statement {
    actions   = ["dynamodb:GetItem"]
    resources = [var.dcr_table_arn]
  }
}

resource "aws_iam_role_policy" "dcr_authorizer_dynamodb" {
  name   = "${local.name_base}-dcr-authorizer-dynamodb"
  role   = aws_iam_role.dcr_authorizer.id
  policy = data.aws_iam_policy_document.dcr_authorizer_dynamodb.json
}

resource "aws_lambda_function" "dcr_authorizer" {
  function_name    = "${local.name_base}-dcr-authorizer"
  role             = aws_iam_role.dcr_authorizer.arn
  handler          = "index.handler"
  runtime          = var.runtime
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256
  timeout          = var.authorizer_timeout

  environment {
    variables = {
      USER_POOL_ID               = var.user_pool_id
      REQUIRED_SCOPE             = "${var.resource_server_identifier}/invoke"
      RESOURCE_SERVER_IDENTIFIER = var.resource_server_identifier
      TABLE_NAME                 = var.dcr_table_name
      # docs/19 §2.4-a: 401化の試行。"throw" で例外を投げたときの API Gateway の応答コードを観測する。
      DENY_MODE                        = var.deny_mode
      REQUIRE_AUDIENCE_FOR_USER_TOKENS = var.require_audience_for_user_tokens
      # WAF-03: CloudFront の秘密ヘッダ(cloudfront_waf.tf)。観測モード(false)から開始
      ORIGIN_VERIFY_SECRET  = var.origin_verify_secret
      ENFORCE_ORIGIN_VERIFY = var.enforce_origin_verify
    }
  }
}

resource "aws_cloudwatch_log_group" "dcr_authorizer" {
  name              = "/aws/lambda/${aws_lambda_function.dcr_authorizer.function_name}"
  retention_in_days = var.log_retention_days
}

# 注: aws_lambda_permission.dcr_authorizer_invoke(移行元 lambda.tf:89-95)は
#     api-gateway モジュールへ移動した(docs/23 §1.3)。

# --- Register Lambda ---

resource "aws_iam_role" "dcr_register" {
  name               = "${local.name_base}-dcr-register-role"
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
    resources = [var.user_pool_arn]
  }
}

resource "aws_iam_role_policy" "dcr_register_cognito" {
  name   = "${local.name_base}-dcr-register-cognito"
  role   = aws_iam_role.dcr_register.id
  policy = data.aws_iam_policy_document.dcr_register_cognito.json
}

data "aws_iam_policy_document" "dcr_register_dynamodb" {
  statement {
    # UpdateItem: 登録数上限(COUNTER#dcr)と IP 単位レート制限(RATE#)のカウンタ
    actions   = ["dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem"]
    resources = [var.dcr_table_arn]
  }
}

resource "aws_iam_role_policy" "dcr_register_dynamodb" {
  name   = "${local.name_base}-dcr-register-dynamodb"
  role   = aws_iam_role.dcr_register.id
  policy = data.aws_iam_policy_document.dcr_register_dynamodb.json
}

resource "aws_lambda_function" "dcr_register" {
  function_name    = "${local.name_base}-dcr-register"
  role             = aws_iam_role.dcr_register.arn
  handler          = "index.handler"
  runtime          = var.runtime
  filename         = data.archive_file.register.output_path
  source_code_hash = data.archive_file.register.output_base64sha256
  timeout          = var.register_timeout

  environment {
    variables = {
      USER_POOL_ID               = var.user_pool_id
      RESOURCE_SERVER_IDENTIFIER = var.resource_server_identifier
      TABLE_NAME                 = var.dcr_table_name
      # MVPのアローリスト(docs/08 §2.4)。運用中に広げられるよう環境変数化。
      ALLOWED_REDIRECT_HOSTS = var.allowed_redirect_hosts
      # docs/19 §2.4-c/d: 既定値・上限は環境変数で運用調整できるようにする
      DEFAULT_TOKEN_ENDPOINT_AUTH_METHOD  = var.default_token_endpoint_auth_method
      MAX_DCR_CLIENTS                     = var.max_dcr_clients
      MAX_REGISTRATIONS_PER_IP_PER_MINUTE = var.max_registrations_per_ip_per_minute
      ACCESS_TOKEN_VALIDITY_MINUTES       = var.access_token_validity_minutes
      APPLY_MANAGED_LOGIN_BRANDING        = var.apply_managed_login_branding
    }
  }
}

resource "aws_cloudwatch_log_group" "dcr_register" {
  name              = "/aws/lambda/${aws_lambda_function.dcr_register.function_name}"
  retention_in_days = var.log_retention_days
}

# 注: aws_lambda_permission.dcr_register_invoke(移行元 lambda.tf:176-182)は
#     api-gateway モジュールへ移動した(docs/23 §1.3)。

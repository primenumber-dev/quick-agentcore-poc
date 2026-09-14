# W3(docs/19-weekly-verification-plan-week5.md §1.3 主案 d): CloudFront + WAF(CLOUDFRONT スコープ)を
# 現行 HTTP API の前段に置く。今週のスパイクでは以下の方針で構築する。
#
# - WAF は全ルール Count で開始し、ハーネス(scripts/waf_attack_tests.py)でラベルと真のクライアントIP(WAF-02)
#   を観測してから locals.waf_mode = "block" に切り替える。
# - オリジン保護の秘密ヘッダ(X-Origin-Verify)は CloudFront から付与し、Lambda Authorizer 側では
#   ENFORCE_ORIGIN_VERIFY=false の観測モードで「付いているか」をログに残すだけにする。
#   強制すると、メタデータが広告する execute-api URL 経由の /authorize /token /register が塞がれるため、
#   カスタムドメインへの URL 移行(D5)と同時に行う必要がある(§1.3、S10 は移行後に判定)。
# - カスタムドメインはドメイン所有の前提が未確定のため今週は CloudFront 既定ドメインで検証する。
#
# 恒久設計・本番移植時は Secrets Manager による秘密ヘッダのローテーション、ログ保全(Firehose → S3 Object Lock)、
# アラームを waf_logging.tf / monitoring.tf として追加する(翌週分)。

provider "aws" {
  alias   = "use1"
  region  = "us-east-1"
  profile = "quick-agentcore-poc-playground"

  default_tags {
    tags = {
      App = "quick-mcp-poc-pattern4-verification"
    }
  }
}

locals {
  # "count" で観測、"block" で遮断。2026-09-13: Count 観測(docs/evidence/2026-09-13-waf-cloudfront-count.json)で
  # 正常系コーパスに Block 対象の誤検知が無いことを確認し block へ切替。
  waf_mode = "block"

  waf_managed_rule_groups = {
    AWSManagedRulesAmazonIpReputationList = { priority = 20, mode = local.waf_mode }
    AWSManagedRulesAnonymousIpList        = { priority = 21, mode = "count" } # HostingProviderIPList は正規クライアント(Claude.ai等)を遮断しうるため恒久 Count
    AWSManagedRulesKnownBadInputsRuleSet  = { priority = 30, mode = local.waf_mode }
    AWSManagedRulesCommonRuleSet          = { priority = 40, mode = local.waf_mode }
    AWSManagedRulesSQLiRuleSet            = { priority = 50, mode = local.waf_mode }
    AWSManagedRulesLinuxRuleSet           = { priority = 60, mode = local.waf_mode }
    AWSManagedRulesUnixRuleSet            = { priority = 61, mode = local.waf_mode }
  }

  # CommonRuleSet 内で誤検知が見込まれるルール(D4)は個別に Count へ上書きする
  common_rule_set_count_overrides = ["SizeRestrictions_BODY", "GenericRFI_BODY", "NoUserAgent_HEADER"]

  api_origin_host = replace(aws_apigatewayv2_api.main.api_endpoint, "https://", "")
}

resource "random_password" "origin_verify" {
  length  = 48
  special = false
}

# --- WAF (CLOUDFRONT scope, us-east-1) ---

resource "aws_wafv2_web_acl" "edge" {
  provider    = aws.use1
  name        = "quick-mcp-poc-edge"
  description = "CloudFront WAF for the MCP server, all routes"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # ボディ検査上限を 64KB に引き上げる(既定 16KB)。日本語の長文引数は UTF-8 で 3 バイト/文字のため 12KB 相当の
  # 入力が 16KB を超え、oversize_handling=MATCH の size 制約に誤検知した(2026-09-13 Count 観測、A25-07)。
  # 16KB 超のリクエストのみ追加課金(AWS WAF: Body inspection size limit)。
  association_config {
    request_body {
      cloudfront {
        default_size_inspection_limit = "KB_64"
      }
    }
  }

  # 1. 許可メソッド以外を遮断(A10)
  rule {
    name     = "method-allowlist"
    priority = 1
    action {
      dynamic "block" {
        for_each = local.waf_mode == "block" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.waf_mode == "block" ? [] : [1]
        content {}
      }
    }
    statement {
      not_statement {
        statement {
          or_statement {
            dynamic "statement" {
              for_each = ["GET", "POST", "DELETE", "OPTIONS", "HEAD"]
              content {
                byte_match_statement {
                  search_string         = statement.value
                  positional_constraint = "EXACTLY"
                  field_to_match {
                    method {}
                  }
                  text_transformation {
                    priority = 0
                    type     = "NONE"
                  }
                }
              }
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "method-allowlist"
      sampled_requests_enabled   = true
    }
  }

  # 2. ボディ 64KB 超を遮断(A13)。CommonRuleSet の SizeRestrictions_BODY(8KB)は Count に上書きする。
  rule {
    name     = "body-over-64kb"
    priority = 2
    action {
      dynamic "block" {
        for_each = local.waf_mode == "block" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.waf_mode == "block" ? [] : [1]
        content {}
      }
    }
    statement {
      size_constraint_statement {
        comparison_operator = "GT"
        size                = 65536
        field_to_match {
          body {
            oversize_handling = "MATCH"
          }
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "body-over-64kb"
      sampled_requests_enabled   = true
    }
  }

  # 3. JSON-RPC バッチ(ボディ先頭 "[")。基準線で v1 SDK サーバーが 50 件を全処理したため(A15)。
  rule {
    name     = "jsonrpc-batch"
    priority = 3
    action {
      dynamic "block" {
        for_each = local.waf_mode == "block" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.waf_mode == "block" ? [] : [1]
        content {}
      }
    }
    statement {
      and_statement {
        statement {
          byte_match_statement {
            search_string         = "/mcp"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        statement {
          byte_match_statement {
            search_string         = "["
            positional_constraint = "STARTS_WITH"
            field_to_match {
              body {
                oversize_handling = "CONTINUE"
              }
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "jsonrpc-batch"
      sampled_requests_enabled   = true
    }
  }

  # 4. レートベース(IP、全ルート)。CloudFront では真のクライアントIPで評価できる(D2 解消)。
  rule {
    name     = "rate-ip"
    priority = 10
    action {
      dynamic "block" {
        for_each = local.waf_mode == "block" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.waf_mode == "block" ? [] : [1]
        content {}
      }
    }
    statement {
      rate_based_statement {
        limit                 = 2000
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-ip"
      sampled_requests_enabled   = true
    }
  }

  # 5. レートベース(Authorization ヘッダ = クライアント/トークン単位、/mcp)。テナント別制限の代替(D6)。
  rule {
    name     = "rate-authorization-mcp"
    priority = 11
    action {
      dynamic "block" {
        for_each = local.waf_mode == "block" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.waf_mode == "block" ? [] : [1]
        content {}
      }
    }
    statement {
      rate_based_statement {
        limit                 = 1000
        evaluation_window_sec = 300
        aggregate_key_type    = "CUSTOM_KEYS"
        custom_key {
          header {
            name = "authorization"
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        scope_down_statement {
          byte_match_statement {
            search_string         = "/mcp"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-authorization-mcp"
      sampled_requests_enabled   = true
    }
  }

  # 6. レートベース(未認証エンドポイント /register /token、低閾値)(A17、A18)
  rule {
    name     = "rate-ip-auth-endpoints"
    priority = 12
    action {
      dynamic "block" {
        for_each = local.waf_mode == "block" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.waf_mode == "block" ? [] : [1]
        content {}
      }
    }
    statement {
      rate_based_statement {
        # 2026-09-14: 一時的に 10 / 60秒 へ下げて機構を実測(全リクエスト 403、docs/evidence/2026-09-14-waf-ratelimit.json)。
        # 実運用値に戻す。閾値は正規クライアントのピークを踏まえて調整する。
        limit                 = 50
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"
        scope_down_statement {
          or_statement {
            statement {
              byte_match_statement {
                search_string         = "/register"
                positional_constraint = "STARTS_WITH"
                field_to_match {
                  uri_path {}
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
            statement {
              byte_match_statement {
                search_string         = "/token"
                positional_constraint = "STARTS_WITH"
                field_to_match {
                  uri_path {}
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-ip-auth-endpoints"
      sampled_requests_enabled   = true
    }
  }

  # マネージドルールグループ
  dynamic "rule" {
    for_each = local.waf_managed_rule_groups
    content {
      name     = rule.key
      priority = rule.value.priority
      override_action {
        dynamic "none" {
          for_each = rule.value.mode == "block" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.mode == "block" ? [] : [1]
          content {}
        }
      }
      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
          dynamic "rule_action_override" {
            for_each = rule.key == "AWSManagedRulesCommonRuleSet" ? local.common_rule_set_count_overrides : []
            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  # Geo は Count で観測のみ(A19。正規クライアントは US 発信)
  rule {
    name     = "geo-observe-non-jp-us"
    priority = 90
    action {
      count {}
    }
    statement {
      not_statement {
        statement {
          geo_match_statement {
            country_codes = ["JP", "US"]
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "geo-observe-non-jp-us"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "quick-mcp-poc-edge"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudwatch_log_group" "waf_edge" {
  provider          = aws.use1
  name              = "aws-waf-logs-quick-mcp-poc-edge"
  retention_in_days = 90
}

resource "aws_wafv2_web_acl_logging_configuration" "edge" {
  provider                = aws.use1
  log_destination_configs = [aws_cloudwatch_log_group.waf_edge.arn]
  resource_arn            = aws_wafv2_web_acl.edge.arn

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}

# --- CloudFront ---

resource "aws_cloudfront_distribution" "edge" {
  enabled         = true
  comment         = "quick-mcp-poc MCP server edge (WAF, origin verify header)"
  price_class     = "PriceClass_200" # 日本を含む
  http_version    = "http2and3"
  is_ipv6_enabled = true
  web_acl_id      = aws_wafv2_web_acl.edge.arn

  origin {
    domain_name = local.api_origin_host
    origin_id   = "http-api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.origin_verify.result
    }
  }

  default_cache_behavior {
    target_origin_id       = "http-api"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false

    # CachingDisabled(マネージド)
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    # AllViewerExceptHostHeader(マネージド): Authorization・クエリ・ボディ関連ヘッダを転送し、Host は API GW のものを使う
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
  }
}

output "cloudfront_domain" {
  value = "https://${aws_cloudfront_distribution.edge.domain_name}"
}

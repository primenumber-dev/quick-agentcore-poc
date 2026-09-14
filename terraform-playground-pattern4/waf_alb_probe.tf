# W2(docs/19-weekly-verification-plan-week5.md §1.6): 現行 internal ALB に Count モードの Web ACL を一時アタッチし、
# (1) 各攻撃パターン(scripts/waf_attack_tests.py)に付くラベル、(2) WAF が評価する送信元IP(WAF-02 / D2:
# VPC Link ENI に集約されるか)、(3) 正常系コーパスの誤検知候補を WAF ログで観測する。
# 検証後はこのファイルを削除して terraform apply する(恒久設定ではない)。
#
# 恒久設計(主案 d: CloudFront + WAF)は別ファイル(waf.tf / cloudfront.tf)で行う。

locals {
  waf_probe_managed_rule_groups = [
    "AWSManagedRulesCommonRuleSet",
    "AWSManagedRulesSQLiRuleSet",
    "AWSManagedRulesKnownBadInputsRuleSet",
    "AWSManagedRulesLinuxRuleSet",
    "AWSManagedRulesUnixRuleSet",
    "AWSManagedRulesAmazonIpReputationList",
    "AWSManagedRulesAnonymousIpList",
  ]
}

resource "aws_wafv2_web_acl" "alb_probe" {
  name        = "quick-mcp-poc-alb-probe"
  description = "Week5 W2 count-mode probe on the internal ALB, temporary"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # レートベース(IP): 低閾値で Count。WAF-02 の観測用(ALB 経由では VPC Link ENI の IP に集約される疑い)
  rule {
    name     = "rate-ip-probe"
    priority = 1

    action {
      count {}
    }

    statement {
      rate_based_statement {
        limit                 = 100
        evaluation_window_sec = 60
        aggregate_key_type    = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-ip-probe"
      sampled_requests_enabled   = true
    }
  }

  # ボディ 64KB 超(カスタム size_constraint、A13)。Count。
  rule {
    name     = "body-over-64kb"
    priority = 2

    action {
      count {}
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

  # JSON-RPC バッチ(ボディ先頭が '[')。A15 で v1 SDK サーバーが 50 件を全処理したため候補ルール。Count。
  rule {
    name     = "jsonrpc-batch"
    priority = 3

    action {
      count {}
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

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "jsonrpc-batch"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = { for i, g in local.waf_probe_managed_rule_groups : g => i + 10 }

    content {
      name     = rule.key
      priority = rule.value

      override_action {
        count {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = rule.key
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "quick-mcp-poc-alb-probe"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "alb_probe" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.alb_probe.arn
}

# WAF ログ(CloudWatch Logs)。ロググループ名は aws-waf-logs- で始まる必要がある。
resource "aws_cloudwatch_log_group" "waf_alb_probe" {
  name              = "aws-waf-logs-quick-mcp-poc-alb-probe"
  retention_in_days = 30
}

resource "aws_wafv2_web_acl_logging_configuration" "alb_probe" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_alb_probe.arn]
  resource_arn            = aws_wafv2_web_acl.alb_probe.arn

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}

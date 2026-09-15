output "web_acl_arn" {
  value       = var.enabled ? aws_wafv2_web_acl.edge[0].arn : null
  description = "CLOUDFRONT スコープの WAF Web ACL ARN(us-east-1)。"
}

# 移行元 cloudfront_waf.tf:490-492 のインライン output を移設したもの。
output "cloudfront_domain" {
  value       = var.enabled ? "https://${aws_cloudfront_distribution.edge[0].domain_name}" : null
  description = "CloudFront ディストリビューションの既定ドメイン(https:// 付き)。"
}

output "cloudfront_distribution_id" {
  value       = var.enabled ? aws_cloudfront_distribution.edge[0].id : null
  description = "CloudFront ディストリビューションID。"
}

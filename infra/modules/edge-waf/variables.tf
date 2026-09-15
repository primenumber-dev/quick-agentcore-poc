variable "name_prefix" {
  type        = string
  description = "リソース名の共通接頭辞(docs/23 §3.1)。WAF ACL 名・ロググループ名・CloudFront コメントに使う。"
  default     = "quick-mcp-poc"
}

variable "resource_suffix" {
  type        = string
  description = "環境識別のためのリソース名接尾辞。**既存の playground スタック(aws_wafv2_web_acl.edge = \"quick-mcp-poc-edge\")に対しては必ず \"\" を渡すこと。** 値を変えると WAF ACL が再作成され、稼働中の CloudFront ディストリビューションから外れる(docs/23 §4)。"
  default     = ""
}

variable "enabled" {
  type        = bool
  description = "false で CloudFront + WAF を作らない。**module ブロックの count ではなくモジュール内リソースの count で切る**(docs/23 §1.4: module への count はモジュール全体を単一グラフノードに潰し、存在しなかった循環を発生させる)。primenumber は当初 false で旧世代と差分ゼロにする(docs/23 §3.2)。"
  default     = true
}

variable "api_endpoint" {
  type        = string
  description = "オリジンとなる HTTP API のエンドポイント。\"https://\" を除去して local.api_origin_host にする(cloudfront_waf.tf:45)。"
}

variable "origin_verify_secret" {
  type        = string
  sensitive   = true
  description = "CloudFront がオリジンへ付与する X-Origin-Verify の値(cloudfront_waf.tf:459)。dcr モジュールも同じ値を参照するため random_password.origin_verify は環境ルートに置き、両モジュールへ渡す(docs/23 §1.3)。再生成すると稼働中の CloudFront と Lambda Authorizer の間に値の不一致窓が開く。"
}

variable "waf_mode" {
  type        = string
  description = "\"count\" で観測、\"block\" で遮断(cloudfront_waf.tf:30)。2026-09-13 の Count 観測で誤検知が無いことを確認して block へ切替済み。"
  default     = "block"

  validation {
    condition     = contains(["count", "block"], var.waf_mode)
    error_message = "waf_mode は \"count\" または \"block\"。"
  }
}

variable "managed_rule_groups" {
  type = map(object({
    priority = number
    mode     = string
  }))
  description = "AWS マネージドルールグループと優先度・モード(cloudfront_waf.tf:32-41)。AWSManagedRulesAnonymousIpList の HostingProviderIPList は正規クライアント(Claude.ai等)を遮断しうるため恒久 count。"
  default = {
    AWSManagedRulesAmazonIpReputationList = { priority = 20, mode = "block" }
    AWSManagedRulesAnonymousIpList        = { priority = 21, mode = "count" }
    AWSManagedRulesKnownBadInputsRuleSet  = { priority = 30, mode = "block" }
    AWSManagedRulesCommonRuleSet          = { priority = 40, mode = "block" }
    AWSManagedRulesSQLiRuleSet            = { priority = 50, mode = "block" }
    AWSManagedRulesLinuxRuleSet           = { priority = 60, mode = "block" }
    AWSManagedRulesUnixRuleSet            = { priority = 61, mode = "block" }
  }
}

variable "common_rule_set_count_overrides" {
  type        = list(string)
  description = "CommonRuleSet 内で誤検知が見込まれ Count へ上書きするルール(D4、cloudfront_waf.tf:43)。"
  default     = ["SizeRestrictions_BODY", "GenericRFI_BODY", "NoUserAgent_HEADER"]
}

variable "body_inspection_limit" {
  type        = string
  description = "WAF のボディ検査上限(cloudfront_waf.tf:71)。既定 16KB では日本語長文(UTF-8 3バイト/文字)が誤検知するため KB_64 に引き上げている(A25-07)。body_size_limit_bytes と一対の決定であり、片方だけ動かすと Week5 の偽陽性が再発する。"
  default     = "KB_64"

  validation {
    condition     = contains(["KB_16", "KB_32", "KB_48", "KB_64"], var.body_inspection_limit)
    error_message = "body_inspection_limit は KB_16 / KB_32 / KB_48 / KB_64 のいずれか。"
  }
}

variable "body_size_limit_bytes" {
  type        = number
  description = "body-over-64kb ルールが遮断するボディサイズの閾値バイト数(cloudfront_waf.tf:138)。body_inspection_limit と必ず一致させること(下の validation を参照。cloudfront_waf.tf:66 の UTF-8 日本語長文の偽陽性は、この2つが片方だけ動くと再発する)。"
  default     = 65536

  validation {
    # cloudfront_waf.tf:65-67 に記録された決定: 検査上限と遮断閾値は「一つの決定の両半分」である。
    # 検査上限より大きな閾値を置くと oversize_handling=MATCH が閾値未満のリクエストを誤検知し、
    # 小さな閾値を置くと検査されないサイズ帯が素通りする。
    condition     = var.body_size_limit_bytes == { KB_16 = 16384, KB_32 = 32768, KB_48 = 49152, KB_64 = 65536 }[var.body_inspection_limit]
    error_message = "body_size_limit_bytes は body_inspection_limit と一致させること(KB_16=16384 / KB_32=32768 / KB_48=49152 / KB_64=65536)。これは cloudfront_waf.tf:66 に記録された一つの決定の両半分であり、片方だけ動かすと日本語長文 UTF-8 の偽陽性が再発する。"
  }
}

variable "rate_ip_limit" {
  type        = number
  description = "rate-ip ルールの上限(cloudfront_waf.tf:226)。CloudFront では真のクライアントIPで評価できる(D2 解消)。"
  default     = 2000
}

variable "rate_authorization_mcp_limit" {
  type        = number
  description = "rate-authorization-mcp ルールの上限(cloudfront_waf.tf:254)。テナント別制限の代替(D6)。"
  default     = 1000
}

variable "rate_auth_endpoints_limit" {
  type        = number
  description = "rate-ip-auth-endpoints(/register /token)ルールの上限(cloudfront_waf.tf:306)。A17・A18。"
  default     = 50
}

variable "rate_evaluation_window_sec" {
  type        = number
  description = "レートベースルール共通の評価ウィンドウ秒数(cloudfront_waf.tf:227,255,307)。"
  default     = 300
}

variable "geo_observe_countries" {
  type        = list(string)
  description = "geo-observe ルールで「これ以外」を Count する国コード(cloudfront_waf.tf:398)。A19: 正規クライアントは US 発信。"
  default     = ["JP", "US"]
}

variable "price_class" {
  type        = string
  description = "CloudFront の価格クラス(cloudfront_waf.tf:440)。PriceClass_200 は日本を含む。"
  default     = "PriceClass_200"
}

variable "cache_policy_id" {
  type        = string
  description = "default_cache_behavior のキャッシュポリシーID(cloudfront_waf.tf:471)。既定はマネージドの CachingDisabled。"
  default     = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
}

variable "origin_request_policy_id" {
  type        = string
  description = "default_cache_behavior のオリジンリクエストポリシーID(cloudfront_waf.tf:473)。既定はマネージドの AllViewerExceptHostHeader。"
  default     = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
}

variable "waf_log_retention_days" {
  type        = number
  description = "WAF ログ(us-east-1 の CloudWatch Logs)の保持日数(cloudfront_waf.tf:420)。"
  default     = 90
}

variable "custom_domain" {
  type = object({
    aliases                  = list(string)
    acm_certificate_arn      = string
    minimum_protocol_version = optional(string, "TLSv1.2_2021")
  })
  description = "カスタムドメイン移行(D5)のフック。null の間は CloudFront 既定ドメイン + 既定証明書で動く(cloudfront_waf.tf:10, :484-487)。ACM 証明書は us-east-1 のもの。"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "全リソースへ付与する追加タグ。provider の default_tags に上乗せされる。"
  default     = {}
}

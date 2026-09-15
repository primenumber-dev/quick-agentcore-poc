# playground 環境ルートの変数宣言。実際の値は terraform.tfvars にある。
#
# 環境固有の値には default を置いていない。tfvars の記入漏れを
# 「それらしい既定値で静かに動く」のではなく、エラーで落とすため。

# --- プロバイダ ---

variable "aws_region" {
  type        = string
  description = "リソースを作るリージョン。移行元は provider.tf:20 で直書きだった。"
}

variable "aws_profile" {
  type        = string
  description = <<-EOT
    AWS プロファイル名。移行元は provider.tf:21 と cloudfront_waf.tf:18 で
    直書きだった (DELIVERY-BLOCKERS DB-03)。
    CI からは GitHub OIDC + AssumeRole に置き換える (00-handoff.md §18.5)。
  EOT
}

variable "default_tags" {
  type        = map(string)
  description = "provider の default_tags。移行元 provider.tf:22-28 の App タグ。"
}

variable "name_prefix" {
  type        = string
  description = "リソース名の共通プレフィックス。"
}

variable "resource_suffix" {
  type        = string
  description = <<-EOT
    リソース名の接尾辞。

    重要: これを全モジュールへ一律に渡してはならない。移行元で接尾辞が
    付いているのは cognito.tf / dynamodb.tf / ssm.tf の 3 ファイルだけで、
    vpc / ecs / alb / ecr / apigateway / lambda / cloudfront_waf のリソース名には
    付いていない。一律に渡すと IAM ロール名・SG 名・TG 名が変わり、
    destroy/create になる (docs/23 §3.1)。
  EOT
}

# --- 世代トグル ---
#
# terraform/ (本番相当) が playground より 1 世代古いという問題 (DB-01) は、
# 別々の .tf を持っていたことが原因だった。3 環境は main.tf を同一に保ち、
# 差分はこの tfvars だけに閉じ込める。構成上ドリフトが起きえなくなる。

variable "enable_dcr" {
  type        = bool
  description = <<-EOT
    DCR 世代を有効にするか。

    true  : Lambda REQUEST Authorizer、/register・/revoke ルート、アクセスログ
            (playground の現行世代)
    false : Cognito JWT Authorizer のみ (terraform/ の旧世代)

    本番相当は当初 false で現行 state と差分ゼロにし、世代マージを意図的な
    別変更として切り出す (docs/23 §5 F1)。
  EOT
}

variable "enable_edge_waf" {
  type        = bool
  description = <<-EOT
    CloudFront + WAF を作るか。本番相当は当初 false (まだ存在しない)。
  EOT
}

variable "enable_local_pool" {
  type        = bool
  description = <<-EOT
    ローカル開発用の 2 つ目の Cognito ユーザープールを作るか。
    本番相当のみ true (terraform/cognito.tf:59-116)。
  EOT
  default     = false
}

# --- ネットワーク ---

variable "vpc_cidr" {
  type        = string
  description = "VPC の CIDR。移行元 vpc.tf:2。ALB の許可元 CIDR にも使う。"
}

variable "public_subnets" {
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  description = "パブリックサブネット。移行元 vpc.tf:11-14。"
}

variable "private_subnets" {
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  description = "プライベートサブネット。移行元 vpc.tf:27-30。"
}

variable "nat_instance_type" {
  type        = string
  description = "NAT インスタンスのタイプ。移行元 vpc.tf:88。NAT Gateway ではない。"
  default     = "t3.nano"
}

variable "nat_ami_name_filter" {
  type        = string
  description = "NAT インスタンスの AMI 名フィルタ。移行元 vpc.tf:77。"
  default     = "amzn2-ami-hvm-*-x86_64-gp2"
}

variable "nat_ami_id" {
  type        = string
  description = <<-EOT
    NAT インスタンスの AMI を固定する。null なら data.aws_ami で最新を引く。

    null のままだと plan が毎回 NAT インスタンス 2 台の置き換えを提案する
    (data.aws_ami が最新 AMI を拾うため)。これは week5 で記録されたドリフトで、
    DCR・WAF とは無関係 (docs/19 §1.9)。moved の適用時に余計な差分を出さないため、
    現在稼働中の AMI ID を入れることを推奨する。
  EOT
  default     = null
}

# --- パラメータ / シークレット ---

variable "ssm_path_prefix" {
  type        = string
  description = <<-EOT
    SSM パラメータのパスプレフィックス。
    ecspresso が ssm_prefix 出力として読み、ECS タスクの IAM 条件にも使われる。
    playground でも本番でも /quick-mcp-poc のままで、resource_suffix は付かない。
  EOT
}

variable "kms_alias_name" {
  type        = string
  description = "SSM 暗号化用 KMS キーのエイリアス。移行元 ssm.tf:19。"
}

variable "ssm_plain_parameters" {
  type = map(object({
    value       = string
    description = string
  }))
  description = "平文の非機微設定。移行元 ssm.tf:23-28。"
  default     = {}
}

variable "ssm_encrypted_parameters" {
  type = map(object({
    payload     = string
    description = string
  }))
  description = <<-EOT
    KMS 暗号文として渡す機密値。playground では未使用 (空)。
    本番相当は terraform/ssm.tf:35,39 の暗号文がここに入る。
    納品先では鍵が同じ apply で作られるため二段階適用になる
    (DELIVERY-BLOCKERS DB-04)。
  EOT
  default     = {}
}

variable "ssm_plaintext_parameters" {
  type = map(object({
    value       = string
    description = string
  }))
  description = <<-EOT
    平文で渡して SecureString 登録する値。移行元 ssm.tf:30-43 のプレースホルダ。

    マップ全体に sensitive を付けていないのは、キーを for_each に使うため
    (sensitive な値は for_each に使えない)。値は parameters モジュール側で
    sensitive() でマークしている。実 credential をここへ書かないこと。
  EOT
  default     = {}
}

# --- DynamoDB ---

variable "dynamodb_table_name" {
  type        = string
  description = "Terraform が作る検証用テーブル。移行元 dynamodb.tf:2。"
}

variable "dcr_table_name" {
  type        = string
  description = <<-EOT
    アプリと DCR Lambda が実際に読むテーブル。Terraform 管理外
    (lambda.tf:5-6 が意図的に管理外と明記)。ARN はこの名前から組み立てる。
    移行元 lambda.tf:9 と ecs.tf:88 はアカウント ID 込みで直書きしていた。
  EOT
}

# --- ECS / ALB ---

variable "container_port" {
  type        = number
  description = "コンテナの待ち受けポート。移行元 ecs.tf:6-7、alb.tf:42。"
  default     = 3000
}

variable "health_check" {
  type = object({
    path                = string
    matcher             = string
    interval            = number
    timeout             = number
    healthy_threshold   = number
    unhealthy_threshold = number
  })
  description = "ターゲットグループのヘルスチェック。移行元 alb.tf:47-54。"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs の保持日数。ECS・Lambda・API GW・WAF で揃える。"
  default     = 90
}

# --- Cognito ---

variable "user_pool_name" {
  type        = string
  description = "Cognito ユーザープール名。移行元 cognito.tf:6。接尾辞が付く。"
}

variable "cognito_domain_prefix" {
  type        = string
  description = <<-EOT
    Cognito ドメインプレフィックス。移行元 cognito.tf:62。

    リージョン内でグローバル一意 (DELIVERY-BLOCKERS DB-07)。playground が
    -pattern4-verify を名乗っているのは quick-mcp-poc-auth が既に取られて
    いたためで、この制約は既に一度実害を出している。
  EOT
}

variable "cognito_callback_urls" {
  type        = list(string)
  description = "許可するコールバック URL。移行元 cognito.tf:41-43。"
}

variable "cognito_explicit_auth_flows" {
  type        = list(string)
  description = "明示的な認証フロー。移行元 cognito.tf:41。本番相当には無い設定。"
  default     = null
}

variable "resource_server_identifier" {
  type        = string
  description = <<-EOT
    Cognito リソースサーバーの識別子。移行元 cognito.tf:50 は API Gateway の
    エンドポイントから導出していた。

    必ず現行の実値を state または
    `terraform output cognito_resource_server_identifier` からコピーすること。
    手打ち禁止。

    これは不透明文字列であり URL として解決されることはない。1 文字でも違うと
    resource server が destroy/create され、発行済み DCR クライアントに付与済みの
    スコープがすべて失われる (docs/23 §1.2)。
  EOT
}

variable "resource_server_name" {
  type        = string
  description = "リソースサーバーの表示名。移行元 cognito.tf:51。接尾辞は付かない。"
}

# --- DCR Lambda ---

variable "lambda_source_dir" {
  type        = string
  description = <<-EOT
    Lambda のビルド成果物ディレクトリ。移行元 lambda.tf:24,30。

    lambda/dist/ は未コミットのため、apply 前に pnpm build が必要。
    この手順は未文書化であり CI/CD 設計の課題 (00-handoff.md §18.5)。
  EOT
}

variable "lambda_runtime" {
  type        = string
  description = "Lambda ランタイム。移行元 lambda.tf:63,149。"
  default     = "nodejs22.x"
}

variable "dcr_authorizer_timeout" {
  type        = number
  description = "Authorizer Lambda のタイムアウト秒。移行元 lambda.tf:66。"
  default     = 5
}

variable "dcr_register_timeout" {
  type        = number
  description = <<-EOT
    Register Lambda のタイムアウト秒。移行元 lambda.tf:152。
    Anthropic の登録応答待ちは 10 秒 (docs/19 §2.1 F10)。
  EOT
  default     = 10
}

variable "dcr_deny_mode" {
  type        = string
  description = "Authorizer の拒否方式。移行元 lambda.tf:75。"
  default     = "throw"
}

variable "dcr_require_audience_for_user_tokens" {
  type        = string
  description = "ユーザートークンに audience 検証を要求するか。移行元 lambda.tf:76。"
  default     = "false"
}

variable "dcr_enforce_origin_verify" {
  type        = string
  description = <<-EOT
    X-Origin-Verify の検証を強制するか。移行元 lambda.tf:79。

    true にできるのはカスタムドメイン移行後 (cloudfront_waf.tf:6-9)。
    現状は観測モードのまま (DELIVERY-BLOCKERS DB-07 の関連項目)。
  EOT
  default     = "false"
}

variable "dcr_allowed_redirect_hosts" {
  type        = string
  description = "DCR で許可するリダイレクト先ホスト。移行元 lambda.tf:160。"
  default     = "claude.ai,claude.com"
}

variable "dcr_default_token_endpoint_auth_method" {
  type        = string
  description = "token_endpoint_auth_method の既定値。移行元 lambda.tf:162。"
  default     = "none"
}

variable "dcr_max_clients" {
  type        = string
  description = "DCR クライアント登録数の上限。移行元 lambda.tf:163。"
  default     = "200"
}

variable "dcr_max_registrations_per_ip_per_minute" {
  type        = string
  description = "IP 単位の登録レート制限。移行元 lambda.tf:164。"
  default     = "5"
}

variable "dcr_access_token_validity_minutes" {
  type        = string
  description = "アクセストークンの有効期間 (分)。移行元 lambda.tf:165。"
  default     = "60"
}

variable "dcr_apply_managed_login_branding" {
  type        = string
  description = <<-EOT
    DCR クライアントに Managed Login ブランディングを適用するか。
    移行元 lambda.tf:166。適用しないとブラウザのログイン画面が表示されない
    (docs/19 §2.1 F6)。
  EOT
  default     = "true"
}

# --- API Gateway ---

variable "api_name" {
  type        = string
  description = "HTTP API の名前。接尾辞は付かない。"
}

variable "apigw_access_log_group_name" {
  type        = string
  description = "API Gateway アクセスログのロググループ名。"
}

variable "register_throttle" {
  type = object({
    burst = number
    rate  = number
  })
  description = "/register ルートのスロットル。移行元 apigateway.tf:96-97。"
}

variable "authorizer_ttl_seconds" {
  type        = number
  description = "Lambda Authorizer の結果キャッシュ秒数。移行元 apigateway.tf:169。"
  default     = 0
}

variable "service_documentation_url" {
  type        = string
  description = "メタデータで広告するドキュメント URL。移行元 apigateway.tf:20。"
}

# --- エッジ (CloudFront + WAF) ---

variable "origin_verify_length" {
  type        = number
  description = "X-Origin-Verify シークレットの長さ。移行元 cloudfront_waf.tf:49。"
  default     = 48
}

variable "waf_mode" {
  type        = string
  description = "WAF の動作モード (count / block)。移行元 cloudfront_waf.tf:30。"
  default     = "block"
}

variable "waf_managed_rule_groups" {
  type = map(object({
    priority = number
    mode     = string
  }))
  description = <<-EOT
    マネージドルールグループと動作の対応。移行元 cloudfront_waf.tf:32-41。
    AnonymousIpList は HostingProviderIPList が正規の MCP クライアントを
    遮断するため恒久的に count (docs/19 §1.1 D3)。
  EOT
}

variable "waf_common_rule_set_count_overrides" {
  type        = list(string)
  description = <<-EOT
    CommonRuleSet 内で count に落とすルール。移行元 cloudfront_waf.tf:43。
    week5 の実測で誤検知が確認されたもの (docs/19 §1.9)。
  EOT
}

variable "waf_body_inspection_limit" {
  type        = string
  description = <<-EOT
    WAF のボディ検査上限。移行元 cloudfront_waf.tf:71。

    既定の 16KB では日本語長文 (UTF-8 で 1 文字 3 バイト) が
    サイズ制約ルールに誤検知する。week5 で KB_64 へ引き上げ済み。
    body_size_limit_bytes と必ず連動させること。
  EOT
  default     = "KB_64"
}

variable "waf_body_size_limit_bytes" {
  type        = number
  description = "カスタムサイズ制約ルールの閾値。移行元 cloudfront_waf.tf:138。"
  default     = 65536
}

variable "waf_geo_observe_countries" {
  type        = list(string)
  description = <<-EOT
    Geo 観測 (count のみ) の対象国。移行元 cloudfront_waf.tf:398。
    MCP クライアントはクラウド発信のため日本限定 Block は不可 (docs/19 §1.1 D3)。
  EOT
  default     = ["JP", "US"]
}

variable "cloudfront_price_class" {
  type        = string
  description = "CloudFront のプライスクラス。移行元 cloudfront_waf.tf:440。"
  default     = "PriceClass_200"
}

# --- ローカル開発用プール (enable_local_pool = true のときのみ使う) ---
#
# 本番相当だけが持つ 2 つ目の Cognito プール (terraform/cognito.tf:59-116)。
# localhost 向けの固定値で、環境間で共有しない。

variable "local_pool_domain_prefix" {
  type        = string
  description = "ローカル用プールのドメインプレフィックス。terraform/cognito.tf:107。"
  default     = null
}

variable "local_pool_callback_urls" {
  type        = list(string)
  description = "ローカル用プールのコールバック URL。terraform/cognito.tf:95-97。"
  default     = null
}

variable "local_pool_resource_server_identifier" {
  type        = string
  description = "ローカル用プールのリソースサーバー識別子。terraform/cognito.tf:102。"
  default     = null
}

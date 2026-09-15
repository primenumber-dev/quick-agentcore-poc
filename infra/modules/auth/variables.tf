variable "name_prefix" {
  type        = string
  description = "全リソース名の接頭辞。現行値は \"quick-mcp-poc\"。"
}

variable "resource_suffix" {
  type        = string
  description = "環境識別のための接尾辞。playgroundは \"-pattern4-verify\"、primenumberは \"\"。移行元でsuffixが付いていた名前にのみ付与する。"
}

variable "region" {
  type        = string
  description = "AWSリージョン。issuer URL と Hosted UI のURL組み立てにのみ使う(モジュール内で data.aws_region は使わない規約のため入力で受け取る)。"
}

variable "user_pool_name" {
  type        = string
  description = "Cognitoユーザープール名。playground: \"quick-mcp-poc-pattern4-verify-users\" / primenumber: \"quick-mcp-poc-users\"。変更するとプールが再作成され全ユーザーが失われる。"
}

variable "password_policy" {
  type = object({
    minimum_length    = number
    require_uppercase = bool
    require_lowercase = bool
    require_numbers   = bool
    require_symbols   = bool
  })
  description = "ユーザープールのパスワードポリシー(cognito.tf:9-15)。"
  default = {
    minimum_length    = 12
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
  }
}

variable "domain_prefix" {
  type        = string
  description = <<-EOT
    Cognito Hosted UI のドメインプレフィックス(cognito.tf:62)。

    納品ブロッカー DB-07: この値は**リージョン内でグローバルに一意**である。playgroundが
    "quick-mcp-poc-pattern4-verify" を名乗っているのは、本番相当アカウントが既に
    "quick-mcp-poc-auth" を確保していたため。新環境では衝突しうるので既定値を置かない。
  EOT
}

variable "callback_urls" {
  type        = list(string)
  description = "アプリクライアントのOAuthコールバックURL(cognito.tf:41-43)。playground: [\"http://localhost:3030/callback\"]。"
}

variable "resource_server_identifier" {
  type        = string
  description = <<-EOT
    Cognito resource server の identifier。
    移行元(cognito.tf:53)では API Gateway の api_endpoint に "/mcp" を連結した式だったが、
    本モジュールでは入力値に置き換えた。これにより auth モジュールから API Gateway への参照はゼロになる。

    ============================ 取り扱い注意 ============================
    * この値は Cognito にとって**不透明文字列**であり、URLとして解決されることはない。
      スコープ名(identifier に "/invoke" を連結したもの)とディスカバリ文書にechoされるだけである。
      したがってカスタムドメインの先行固定は不要で、移行はtfvars 1行の変更で足りる。

    * **既存プールでは、現在の実値と完全に一致させること。**
      取得方法: `terraform output cognito_resource_server_identifier`
      (terraform-playground-pattern4/outputs.tf:46-48)または tfstate から読む。**手打ち禁止。**

    * **1文字でも違えば aws_cognito_resource_server が destroy / create される。**
      その結果、発行済みDCRクライアントに付与された invoke スコープが**すべて失われ**、
      稼働中のクライアントが一斉に認可エラーになる(docs/23 §1.2)。
    =====================================================================
  EOT
}

variable "resource_server_name" {
  type        = string
  description = "Cognito resource server の表示名(cognito.tf:57)。現行値 \"quick-mcp-poc-mcp\"。"
}

variable "extra_oauth_scopes" {
  type        = list(string)
  description = "アプリクライアントの allowed_oauth_scopes に追加するスコープ。既定の openid / email / profile / <identifier>/invoke に連結される。"
  default     = []
}

variable "explicit_auth_flows" {
  type        = list(string)
  description = <<-EOT
    アプリクライアントの explicit_auth_flows(cognito.tf:39)。
    playground は検証用に ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"] を設定している。
    terraform/(本番相当)世代は未設定であるため、既定は null(=未設定)とし、
    本番相当環境で意図せず USER_PASSWORD 認証が有効化されるのを防ぐ。
  EOT
  default     = null
}

variable "branding_settings" {
  type        = string
  description = "Managed Login のブランディング設定JSON文字列(cognito_branding.tf:2)。null の場合はモジュール内蔵の既定設定を使う。"
  default     = null
}

variable "enable_local_pool" {
  type        = bool
  description = "ローカル開発用の2つ目のユーザープール一式(terraform/cognito.tf:59-116)を作成するか。playground / 本番相当ともに false。"
  default     = false
}

variable "local_pool_callback_urls" {
  type        = list(string)
  description = "ローカル開発用プールのコールバックURL(terraform/cognito.tf:95-97)。enable_local_pool が false のときは無視される。"
  default     = ["http://localhost:3000/callback"]
}

variable "local_pool_resource_server_identifier" {
  type        = string
  description = "ローカル開発用プールの resource server identifier(terraform/cognito.tf:102)。"
  default     = "http://localhost:8080/mcp"
}

variable "local_pool_domain_prefix" {
  type        = string
  description = "ローカル開発用プールの Hosted UI ドメインプレフィックス(terraform/cognito.tf:107)。domain_prefix 同様リージョン内でグローバル一意。"
  default     = "local-quick-mcp-poc-auth"
}

variable "tags" {
  type        = map(string)
  description = "全リソースに付与する追加タグ。Name タグはモジュール側で上書きする。"
  default     = {}
}

variable "name_prefix" {
  type        = string
  description = "リソース名の共通プレフィックス (例: quick-mcp-poc)。"
}

variable "resource_suffix" {
  type        = string
  description = <<-EOT
    リソース名の接尾辞。playground では "-pattern4-verify"、その他は ""。

    注意: この接尾辞が付くのは cognito / dynamodb / ssm の 3 系統だけで、
    network や ecs には付かない。全モジュールに一律で渡すと IAM ロール名や
    セキュリティグループ名が変わり、destroy/create になる。
    docs/23-weekly-verification-plan-week6.md §3.1 を参照。
  EOT
  default     = ""
}

variable "ssm_path_prefix" {
  type        = string
  description = <<-EOT
    SSM パラメータ名のパスプレフィックス (例: /quick-mcp-poc)。
    各パラメータ名は ssm_path_prefix にマップのキーを連結して組み立てる。

    注意: これはリソース名ではなくパラメータのパスであり、resource_suffix は付かない。
    playground でも本番でも /quick-mcp-poc のままである
    (ecs.tf:108 の IAM 条件と ecspresso の ssm_prefix 出力が依存している)。
  EOT
}

variable "kms_alias_name" {
  type        = string
  description = "SSM 暗号化用 KMS キーのエイリアス (例: alias/quick-mcp-poc-ssm)。"
}

# --- パラメータの 3 系統 ---
#
# 移行元の 2 世代が同じものを別々の書き方で持っていたため、3 つの入力に分けている。
# それぞれ別のリソースラベルに対応しており、使わない系統は空マップにしておけば
# リソースが 1 つも作られない。これにより playground と primenumber の
# 両方が差分ゼロで moved できる (docs/23 §4)。
#
#   plain_parameters     -> aws_ssm_parameter.ssm_plain_parameters
#                           平文の非機微設定。String。
#   encrypted_parameters -> aws_ssm_parameter.ssm_parameters
#                           KMS 暗号文をコミットする方式。SecureString。
#                           primenumber (terraform/ssm.tf:32-43) が使っている。
#   plaintext_parameters -> aws_ssm_parameter.ssm_plaintext_parameters
#                           値を平文で渡して SecureString として登録する。
#                           playground のプレースホルダ (ssm.tf:30-43) 用。

variable "plain_parameters" {
  type = map(object({
    value       = string
    description = string
  }))
  description = <<-EOT
    平文で登録する非機微な設定値。String 型として登録される。
    キーは ssm_path_prefix に続くパス (例: "/quick-api/base")。
  EOT
  default     = {}
}

variable "encrypted_parameters" {
  type = map(object({
    payload     = string
    description = string
  }))
  description = <<-EOT
    KMS 暗号文 (base64 CiphertextBlob) として渡す機密値。SecureString として登録される。
    payload は scripts/encrypt-secret.sh が生成する
    (aws kms encrypt --key-id <kms_alias_name> 相当)。

    payload が空文字のエントリはプレースホルダとして扱われスキップされる。
    これは納品先での二段階適用を成立させるための仕掛けである:

      1 回目: encrypted_parameters = {} で apply し、KMS キーを作る
      2 回目: そのキーで暗号化した payload を入れて再 apply

    暗号文は作成したアカウントの KMS キーに紐づくため、別アカウントでは
    復号できず apply が必ず失敗する。詳細と推奨する代替案 (暗号文をコミット
    せず帯域外で put-parameter する方式) は
    docs/fde/DELIVERY-BLOCKERS.md の DB-04 を参照。
  EOT
  default     = {}
}

variable "plaintext_parameters" {
  type = map(object({
    value       = string
    description = string
  }))
  description = <<-EOT
    値を平文で受け取り SecureString として登録する機密値。
    playground のプレースホルダ用であり、実 credential をここへ書かないこと。

    マップ全体には sensitive を付けられない。sensitive な値は for_each に
    使えず (インスタンスキーとして露出しうるため)、キーはパラメータのパスで
    あって秘密ではない。値だけを main.tf 側で sensitive() でマークしている。
  EOT
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = <<-EOT
    追加タグ。移行元は provider の default_tags だけでタグ付けしていたため、
    差分ゼロで移行するには {} を渡すこと (docs/23 §3.1)。
  EOT
  default     = {}
}

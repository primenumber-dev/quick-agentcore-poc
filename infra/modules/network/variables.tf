variable "name_prefix" {
  type        = string
  description = "全リソース名の先頭に付く共通プレフィックス(例: quick-mcp-poc)。"
}

variable "resource_suffix" {
  type        = string
  description = "環境識別用のサフィックス(例: -pattern4-verify)。注意: 移行元 terraform-playground-pattern4/vpc.tf のNameタグは -pattern4-verify を含まず \"quick-mcp-poc-vpc\" 等の素の形である。既存stateを引き継ぐ環境では空文字を渡し、名前をバイト等価に保つこと(渡すとNameタグ差分が出る)。"
  default     = ""
}

variable "vpc_cidr" {
  type        = string
  description = "VPCのCIDRブロック。移行元: terraform-playground-pattern4/vpc.tf:2。"
}

variable "public_subnets" {
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  description = "パブリックサブネットの定義。キーがサブネットの識別子(例: az-a)になり、リソース名とfor_eachキーの両方に使われる。移行元: terraform-playground-pattern4/vpc.tf:11-14。"
}

variable "private_subnets" {
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  description = "プライベートサブネットの定義。キーはNATインスタンス・プライベートルートテーブルのfor_eachキーと対応する。移行元: terraform-playground-pattern4/vpc.tf:27-30。"
}

variable "nat_instance_type" {
  type        = string
  description = "NATインスタンスのインスタンスタイプ。移行元: terraform-playground-pattern4/vpc.tf:88。"
  default     = "t3.nano"
}

variable "nat_ami_name_filter" {
  type        = string
  description = "NATインスタンス用AMIのnameフィルタ。移行元: terraform-playground-pattern4/vpc.tf:77。"
  default     = "amzn2-ami-hvm-*-x86_64-gp2"
}

# data.aws_ami は most_recent = true のため、新しいAMIが公開されるたびに
# plan がNATインスタンス2台の置き換えを提案する(docs/19 §1.9 に記録されたAMIドリフト)。
# 本変数にAMI IDを明示するとデータソース参照を使わなくなり、ドリフトが止まる。
# 既存環境では state 上の実AMI IDをコピーして設定すること(手打ち禁止)。
variable "nat_ami_id" {
  type        = string
  description = "NATインスタンスに固定するAMI ID。null の場合は data.aws_ami による最新AMI検索を使う(AMIドリフトが発生する)。"
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "全リソースに付与する共通タグ。"
  default     = {}
}

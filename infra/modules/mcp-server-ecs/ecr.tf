# コンテナイメージのリポジトリ。移行元は terraform-playground-pattern4/ecr.tf。
#
# リポジトリ名に resource_suffix は付かない。移行元は playground でも
# "quick-mcp-poc" のままであり (ecr.tf:2)、接尾辞を付けるとリポジトリが
# 作り直しになりイメージを失う。docs/23 §3.1 を参照。

resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repository_name != null ? var.ecr_repository_name : var.name_prefix
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  tags = var.tags
}

variable "ecr_repository_name" {
  type        = string
  description = "ECR リポジトリ名。null なら name_prefix をそのまま使う (接尾辞は付けない)。"
  default     = null
}

variable "ecr_image_tag_mutability" {
  type        = string
  description = <<-EOT
    タグの可変性。移行元は IMMUTABLE。
    IMMUTABLE のため同一タグの再 push ができない点は CI/CD 設計の制約になる
    (00-handoff.md §18.5)。
  EOT
  default     = "IMMUTABLE"
}

variable "ecr_scan_on_push" {
  type        = bool
  description = "push 時の脆弱性スキャンを有効にするか。"
  default     = true
}

variable "ecr_keep_last_images" {
  type        = number
  description = "ライフサイクルポリシーで保持する直近イメージ数。"
  default     = 10
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.ecr_keep_last_images} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_keep_last_images
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ecspresso が ecs-task-def.json:10 で tfstate 経由に名前で読む出力。
# 改名すると Terraform エラーではなく難解な ecspresso テンプレートエラーになる
# (docs/23 §3.3)。
output "ecr_repository_url" {
  description = "ECR リポジトリの URL。ecspresso の ecr_repository_url 出力の元。"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "ECR リポジトリ名。"
  value       = aws_ecr_repository.app.name
}

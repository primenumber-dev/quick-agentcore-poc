terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.24"
    }
  }
}

locals {
  name = "${var.name_prefix}${var.resource_suffix}"
}

# --------------------------------------------------------------------------
# ALB(移行元: terraform-playground-pattern4/alb.tf:1-59)
# ターゲットグループとリスナーはECSの受け口であるため network ではなくここに置く。
# --------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name   = "${local.name}-alb-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.alb_ingress_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_lb" "main" {
  name                       = "${local.name}-alb"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.private_subnet_ids
  drop_invalid_header_fields = true

  tags = var.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = var.tags
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    interval            = var.health_check.interval
    timeout             = var.health_check.timeout
    healthy_threshold   = var.health_check.healthy_threshold
    unhealthy_threshold = var.health_check.unhealthy_threshold
    path                = var.health_check.path
    matcher             = var.health_check.matcher
  }

  tags = merge(var.tags, {
    Name = "${local.name}-tg"
  })
}

# --------------------------------------------------------------------------
# ECS(移行元: terraform-playground-pattern4/ecs.tf:1-128)
# --------------------------------------------------------------------------

resource "aws_security_group" "ecs" {
  name   = "${local.name}-ecs-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-ecs-sg"
  })
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name}-cluster"

  tags = merge(var.tags, {
    Name = "${local.name}-cluster"
  })
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.name}-ecs-task-execution-role"
  })
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_ssm" {
  name   = "${local.name}-ecs-task-execution-ssm"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_ssm.json
}


resource "aws_iam_role" "ecs_app_task" {
  name               = "${local.name}-ecs-app-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.name}-ecs-app-task-role"
  })
}

resource "aws_iam_role_policy" "ecs_app_task_dynamodb" {
  name   = "${local.name}-ecs-app-task-dynamodb"
  role   = aws_iam_role.ecs_app_task.id
  policy = data.aws_iam_policy_document.ecs_app_task_dynamodb.json
}

data "aws_iam_policy_document" "ecs_app_task_dynamodb" {
  statement {
    actions = [
      "dynamodb:GetItem",
    ]
    # 移行元 ecs.tf:83-89 は2要素を直接列挙していた。原文のコメントを保存する:
    #   アプリコード(server/src/db.ts)がテーブル名"quick-mcp-poc-users"をハードコードしているため、
    #   実際に読まれるのはこの検証用に新規作成したテーブルではなく、AgentCore Runtime検証(§で作成済み)の
    #   既存テーブル。両方への権限を許可しておく。
    # ここでは両方を var.dynamodb_table_arns のリストとして環境ルートから受け取る
    # (2要素目はアカウントID 883660531246 を直書きしていたため変数化が必須だった)。
    resources = var.dynamodb_table_arns
  }
}

resource "aws_iam_role_policy" "ecs_app_task_ssm" {
  name   = "${local.name}-ecs-app-task-ssm"
  role   = aws_iam_role.ecs_app_task.id
  policy = data.aws_iam_policy_document.ecs_ssm.json
}

# Shared by both roles: the execution role resolves task-def `secrets` at startup,
# and the task role can also fetch SSM directly at runtime if needed.
data "aws_iam_policy_document" "ecs_ssm" {
  statement {
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
    ]
    resources = [
      "arn:aws:ssm:${var.region}:${var.account_id}:parameter${var.ssm_path_prefix}/*",
    ]
  }
  statement {
    actions = [
      "kms:Decrypt",
    ]
    resources = [
      var.ssm_kms_key_arn,
    ]
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  # 移行元 ecs.tf:122 は "/quick-mcp-poc/ecs"。接尾辞を含まないため name_prefix のみで組む。
  name              = "/${var.name_prefix}/ecs"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${local.name}-ecs-log-group"
  })
}

resource "aws_security_group" "ecs" {
  name   = "quick-mcp-poc-ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "quick-mcp-poc-ecs-sg"
  }
}

resource "aws_ecs_cluster" "main" {
  name = "quick-mcp-poc-cluster"

  tags = {
    Name = "quick-mcp-poc-cluster"
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "quick-mcp-poc-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Name = "quick-mcp-poc-ecs-task-execution-role"
  }
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
  name   = "quick-mcp-poc-ecs-task-execution-ssm"
  role   = aws_iam_role.ecs_task_execution.id
  policy = data.aws_iam_policy_document.ecs_ssm.json
}


resource "aws_iam_role" "ecs_app_task" {
  name               = "quick-mcp-poc-ecs-app-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json

  tags = {
    Name = "quick-mcp-poc-ecs-app-task-role"
  }
}

resource "aws_iam_role_policy" "ecs_app_task_dynamodb" {
  name   = "quick-mcp-poc-ecs-app-task-dynamodb"
  role   = aws_iam_role.ecs_app_task.id
  policy = data.aws_iam_policy_document.ecs_app_task_dynamodb.json
}

data "aws_iam_policy_document" "ecs_app_task_dynamodb" {
  statement {
    actions = [
      "dynamodb:GetItem",
    ]
    resources = [
      aws_dynamodb_table.mcp_users.arn,
    ]
  }
}

resource "aws_iam_role_policy" "ecs_app_task_ssm" {
  name   = "quick-mcp-poc-ecs-app-task-ssm"
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
      "arn:aws:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter/quick-mcp-poc/*",
    ]
  }
  statement {
    actions = [
      "kms:Decrypt",
    ]
    resources = [
      aws_kms_key.ssm.arn,
    ]
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/quick-mcp-poc/ecs"
  retention_in_days = 90

  tags = {
    Name = "quick-mcp-poc-ecs-log-group"
  }
}

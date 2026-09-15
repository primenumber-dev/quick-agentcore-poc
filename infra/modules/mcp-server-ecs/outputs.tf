output "cluster_name" {
  description = "ECSクラスタ名。ecspresso の cluster 指定に使う。"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECSクラスタのARN。"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_security_group_id" {
  description = "ECSタスク用セキュリティグループのID。ルート出力 ecs_security_group_id(ecspresso互換契約)の元。"
  value       = aws_security_group.ecs.id
}

output "task_execution_role_arn" {
  description = "ECSタスク実行ロールのARN。ルート出力 ecs_task_execution_role_arn の元。"
  value       = aws_iam_role.ecs_task_execution.arn
}

output "app_task_role_arn" {
  description = "アプリタスクロールのARN。ルート出力 ecs_app_task_role_arn の元。"
  value       = aws_iam_role.ecs_app_task.arn
}

output "log_group_name" {
  description = "ECSコンテナログのCloudWatch Logsグループ名。ルート出力 ecs_cloudwatch_log_group_name の元。"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "alb_security_group_id" {
  description = "内部ALB用セキュリティグループのID。"
  value       = aws_security_group.alb.id
}

output "alb_dns_name" {
  description = "内部ALBのDNS名。API Gateway の VPC Link 統合先として使う。"
  value       = aws_lb.main.dns_name
}

output "alb_listener_arn" {
  description = "内部ALBのHTTPリスナーARN。API Gateway の VPC Link 統合が参照する。"
  value       = aws_lb_listener.http.arn
}

output "target_group_arn" {
  description = "アプリのターゲットグループARN。ルート出力 alb_target_group_arn(ecspresso互換契約)の元。"
  value       = aws_lb_target_group.app.arn
}

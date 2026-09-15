# スタブ。参照すべきリソースがまだ存在しないため、値は null のプレースホルダである。
# 実装時に実リソースの属性へ差し替える。呼び出し側がこの出力を利用する場合、
# 現時点では必ず null が返ることに注意すること。

output "agentcore_runtime_arn" {
  value       = null
  description = "【未実装】AgentCore Runtime の ARN。現状は null を返すプレースホルダ。"
}

output "invoke_endpoint" {
  value       = null
  description = "【未実装】AgentCore Runtime の呼び出しエンドポイントURL。現状は null を返すプレースホルダ。"
}

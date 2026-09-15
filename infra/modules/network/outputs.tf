output "vpc_id" {
  description = "VPCのID。"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPCのCIDRブロック。ALBのingress CIDR(alb_ingress_cidrs)の既定値として使う。"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "パブリックサブネットIDのマップ(キーは public_subnets のキー)。"
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "プライベートサブネットIDのマップ(キーは private_subnets のキー)。"
  value       = { for k, s in aws_subnet.private : k => s.id }
}

output "private_subnet_ids_list" {
  description = "プライベートサブネットIDのリスト。ALBのsubnetsやecspressoのawsvpcConfigurationが要求する形。"
  value       = [for s in aws_subnet.private : s.id]
}

output "private_subnet_cidrs" {
  description = "プライベートサブネットのCIDRリスト。移行元 vpc.tf:144 のNAT SG ingressと同じ値。"
  value       = [for s in aws_subnet.private : s.cidr_block]
}

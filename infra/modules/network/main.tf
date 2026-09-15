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

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${local.name}-vpc"
  })
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${local.name}-${each.key}-public"
  })
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = merge(var.tags, {
    Name = "${local.name}-${each.key}-private"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${local.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# var.nat_ami_id が指定されている場合はデータソース自体を評価しない(count = 0)。
# most_recent = true は新AMI公開のたびにNATインスタンスの置き換えを提案するため
# (docs/19 §1.9 のAMIドリフト)、既存環境では nat_ami_id を固定するのが対処。
data "aws_ami" "amazon_linux" {
  count = var.nat_ami_id == null ? 1 : 0

  most_recent = true
  owners      = ["amazon"]

  # AL2(yum + iptables-services)を使う。AL2023はnftables前提で
  # user_dataのiptables-services導入スクリプトと相性が悪いため避ける。
  filter {
    name   = "name"
    values = [var.nat_ami_name_filter]
  }
}

resource "aws_instance" "nat" {
  for_each = { for k, v in var.private_subnets : k => k }

  ami                    = var.nat_ami_id != null ? var.nat_ami_id : data.aws_ami.amazon_linux[0].id
  instance_type          = var.nat_instance_type
  subnet_id              = aws_subnet.public[each.value].id
  vpc_security_group_ids = [aws_security_group.nat.id]
  source_dest_check      = false

  user_data = <<-EOF
    #!/bin/bash
    yum install iptables-services -y

    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/custom-ip-forwarding.conf
    sysctl -p /etc/sysctl.d/custom-ip-forwarding.conf

    systemctl enable iptables
    systemctl start iptables

    PRIMARY_NIC=$(ip -o -4 route show to default | awk '{print $5}')

    /sbin/iptables -t nat -A POSTROUTING -o $${PRIMARY_NIC} -j MASQUERADE
    /sbin/iptables -F FORWARD

    service iptables save
  EOF

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  tags = merge(var.tags, {
    Name = "${local.name}-${each.key}-nat"
  })
}

resource "aws_eip" "nat" {
  for_each = aws_instance.nat

  instance = each.value.id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${local.name}-${each.key}-nat-eip"
  })
}

resource "aws_security_group" "nat" {
  name   = "${local.name}-nat-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [for s in aws_subnet.private : s.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_route_table" "private" {
  for_each = aws_instance.nat

  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = each.value.primary_network_interface_id
  }

  tags = merge(var.tags, {
    Name = "${local.name}-${each.key}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

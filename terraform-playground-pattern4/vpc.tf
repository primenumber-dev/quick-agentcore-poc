resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "quick-mcp-poc-vpc"
  }
}

resource "aws_subnet" "public" {
  for_each = {
    "az-a" = { cidr_block = "10.0.1.0/24", availability_zone = "ap-northeast-1a" }
    "az-c" = { cidr_block = "10.0.2.0/24", availability_zone = "ap-northeast-1c" }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "quick-mcp-poc-${each.key}-public"
  }
}

resource "aws_subnet" "private" {
  for_each = {
    "az-a" = { cidr_block = "10.0.10.0/24", availability_zone = "ap-northeast-1a" }
    "az-c" = { cidr_block = "10.0.11.0/24", availability_zone = "ap-northeast-1c" }
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    Name = "quick-mcp-poc-${each.key}-private"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "quick-mcp-poc-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "quick-mcp-poc-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  # AL2(yum + iptables-services)を使う。AL2023はnftables前提で
  # user_dataのiptables-services導入スクリプトと相性が悪いため避ける。
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "nat" {
  for_each = {
    "az-a" = "az-a"
    "az-c" = "az-c"
  }

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.nano"
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

  tags = {
    Name = "quick-mcp-poc-${each.key}-nat"
  }
}

resource "aws_eip" "nat" {
  for_each = aws_instance.nat

  instance = each.value.id
  domain   = "vpc"

  tags = {
    Name = "quick-mcp-poc-${each.key}-nat-eip"
  }
}

resource "aws_security_group" "nat" {
  name   = "quick-mcp-poc-nat-sg"
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
}

resource "aws_route_table" "private" {
  for_each = aws_instance.nat

  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = each.value.primary_network_interface_id
  }

  tags = {
    Name = "quick-mcp-poc-${each.key}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}


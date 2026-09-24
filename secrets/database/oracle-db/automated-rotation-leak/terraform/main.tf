

resource "random_id" "suffix" {
  byte_length = 3
}

resource "random_password" "ssh" {
  length  = 32
  special = false
}

locals {
  name = "${var.name_prefix}-${random_id.suffix.hex}"
  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    region_b64   = base64encode(var.aws_region)
    kms_b64      = base64encode(aws_kms_key.unseal.key_id)
    license_b64  = base64encode(trimspace(var.vault_license))
    password_b64 = base64encode(random_password.ssh.result)
    scripts = {
      "bootstrap.sh" = filebase64("${path.module}/../scripts/bootstrap.sh")
      "configure.sh" = filebase64("${path.module}/../scripts/configure.sh")
      "monitor.sh"   = filebase64("${path.module}/../scripts/monitor.sh")
      "fault.sh"     = filebase64("${path.module}/../scripts/fault.sh")
    }
  })
}

data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = local.name }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
}

resource "aws_subnet" "lab" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}

resource "aws_route_table" "lab" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
}

resource "aws_route_table_association" "lab" {
  subnet_id      = aws_subnet.lab.id
  route_table_id = aws_route_table.lab.id
}

resource "aws_security_group" "lab" {
  name_prefix = "${local.name}-"
  description = "SSH only; Vault and Oracle are accessed from the host"
  vpc_id      = aws_vpc.lab.id
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.lab.id
  cidr_ipv4         = var.ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.lab.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_kms_key" "unseal" {
  description             = "Auto-unseal for ${local.name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "unseal" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.unseal.key_id
}

resource "aws_iam_role" "lab" {
  name = local.name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "unseal" {
  role = aws_iam_role.lab.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
      Resource = aws_kms_key.unseal.arn
    }]
  })
}

resource "aws_iam_instance_profile" "lab" {
  name = local.name
  role = aws_iam_role.lab.name
}

resource "aws_instance" "lab" {
  ami                         = data.aws_ssm_parameter.ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.lab.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.lab.name
  user_data_base64            = base64gzip(local.user_data)
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = local.name }
  depends_on = [
    aws_route_table_association.lab,
    aws_iam_role_policy.unseal,
    aws_vpc_security_group_egress_rule.all,
  ]

  lifecycle {
    precondition {
      condition     = length(base64gzip(local.user_data)) <= 21844
      error_message = "Compressed user data exceeds EC2's 16-KiB raw limit."
    }
  }
}

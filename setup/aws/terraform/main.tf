locals {
  common_tags = merge(
    {
      Project     = var.name_prefix
      Scenario    = "vault-aws-dev-sandbox"
      ManagedBy   = "terraform"
      Environment = "repro"
      "vault-repro" = "true"
    },
    var.extra_tags,
  )
}

data "aws_vpc" "default" {
  default = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_subnet" "default" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = data.aws_availability_zones.available.names[0]
  default_for_az    = true
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "vault" {
  name        = "${var.name_prefix}-sg"
  description = "SSH access for ${var.name_prefix} Vault dev sandbox"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.name_prefix}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_admin" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = var.admin_ssh_cidr
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
  description       = "Admin SSH access"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound access for package and binary downloads"
}

resource "aws_instance" "vault" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = data.aws_subnet.default.id
  vpc_security_group_ids      = [aws_security_group.vault.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    vault_version     = var.vault_version
    vault_license_b64 = base64encode(var.vault_license)
  })

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = var.name_prefix
  }
}

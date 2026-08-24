locals {
  common_tags = merge(
    {
      Project      = var.name_prefix
      Scenario     = "vault-ui-login-default-auth-repro"
      ManagedBy    = "terraform"
      Environment  = "repro"
      "vault-repro" = "true"
    },
    var.extra_tags,
  )

  node_count = 3

  nodes = {
    "1" = { node_id = "vault-1" }
    "2" = { node_id = "vault-2" }
    "3" = { node_id = "vault-3" }
  }
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

resource "aws_kms_key" "vault_unseal" {
  description             = "${var.name_prefix} Vault auto-unseal key"
  deletion_window_in_days = 7
  enable_key_rotation     = false

  tags = {
    Name = "${var.name_prefix}-unseal-key"
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.name_prefix}-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

resource "aws_iam_role" "vault" {
  name = "${var.name_prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vault_kms" {
  name = "${var.name_prefix}-kms-policy"
  role = aws_iam_role.vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VaultKMSUnseal"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
        ]
        Resource = aws_kms_key.vault_unseal.arn
      },
      {
        Sid      = "VaultRaftAutoJoin"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "vault" {
  name = "${var.name_prefix}-profile"
  role = aws_iam_role.vault.name
}

resource "aws_security_group" "vault" {
  name        = "${var.name_prefix}-sg"
  description = "Vault cluster nodes for ${var.name_prefix}"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${var.name_prefix}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = var.admin_ssh_cidr
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
  description       = "Admin SSH"
}

resource "aws_vpc_security_group_ingress_rule" "vault_api" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = var.admin_ssh_cidr
  from_port         = 8200
  ip_protocol       = "tcp"
  to_port           = 8200
  description       = "Vault API from admin CIDR"
}

resource "aws_vpc_security_group_ingress_rule" "vault_cluster_internal" {
  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.vault.id
  from_port                    = 8200
  ip_protocol                  = "tcp"
  to_port                      = 8201
  description                  = "Vault API and cluster RPC between nodes"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound access"
}

resource "aws_instance" "vault" {
  for_each = local.nodes

  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = data.aws_subnet.default.id
  vpc_security_group_ids      = [aws_security_group.vault.id]
  iam_instance_profile        = aws_iam_instance_profile.vault.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    vault_version     = var.vault_version
    vault_license_b64 = base64encode(var.vault_license)
    node_id           = each.value.node_id
    kms_key_id        = aws_kms_key.vault_unseal.key_id
    aws_region        = var.aws_region
  })

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.name_prefix}-${each.value.node_id}"
  }
}

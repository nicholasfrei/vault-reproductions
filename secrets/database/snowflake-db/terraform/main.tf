locals {
  common_tags = merge(
    {
      Project     = var.name_prefix
      Scenario    = "vault-db-role-update-partial-payload"
      ManagedBy   = "terraform"
      Environment = "repro"
    },
    var.extra_tags,
  )

  node_id     = "${var.name_prefix}-node-1"
  private_ip  = cidrhost(var.subnet_cidr, 10)
  cluster_name = "${var.name_prefix}-cluster"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "hc_base_al2023" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["888995627335"] # ami-prod account

  filter {
    name   = "name"
    values = [format("hc-base-al2023-%s-*", var.ami_architecture)]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ─── Networking ───────────────────────────────────────────────────────────────

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ─── Security Group ───────────────────────────────────────────────────────────

resource "aws_security_group" "vault" {
  name        = "${var.name_prefix}-vault-sg"
  description = "Vault node for db-role update partial payload repro"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-vault-sg"
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

resource "aws_vpc_security_group_ingress_rule" "vault_api_admin" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = var.admin_ssh_cidr
  from_port         = 8200
  ip_protocol       = "tcp"
  to_port           = 8200
  description       = "Admin Vault API access"
}

resource "aws_vpc_security_group_egress_rule" "vault_all" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound access for package downloads"
}

# ─── KMS Auto-Unseal ──────────────────────────────────────────────────────────

resource "aws_kms_key" "vault_unseal" {
  description             = "Vault auto-unseal key for ${var.name_prefix}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.name_prefix}-vault-unseal"
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.name_prefix}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

# ─── IAM Instance Profile ─────────────────────────────────────────────────────

resource "aws_iam_role" "vault_node" {
  name = "${var.name_prefix}-vault-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${var.name_prefix}-vault-node"
  }
}

resource "aws_iam_role_policy" "vault_kms_unseal" {
  name = "${var.name_prefix}-vault-kms-unseal"
  role = aws_iam_role.vault_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      Resource = aws_kms_key.vault_unseal.arn
    }]
  })
}

resource "aws_iam_instance_profile" "vault_node" {
  name = "${var.name_prefix}-vault-node"
  role = aws_iam_role.vault_node.name
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "vault" {
  ami                         = coalesce(var.ami_id, one(data.aws_ami.hc_base_al2023[*].image_id))
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public.id
  private_ip                  = local.private_ip
  vpc_security_group_ids      = [aws_security_group.vault.id]
  iam_instance_profile        = aws_iam_instance_profile.vault_node.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    node_id           = local.node_id
    node_private_ip   = local.private_ip
    cluster_name      = local.cluster_name
    vault_version     = var.vault_version
    vault_log_level   = var.vault_log_level
    vault_license_b64 = base64encode(var.vault_license)
    kms_key_id        = aws_kms_key.vault_unseal.key_id
    aws_region        = var.aws_region
  })

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name          = local.node_id
    vault-cluster = local.cluster_name
    vault-node-id = local.node_id
    vault-role    = "voter"
  }
}

locals {
  common_tags = merge(
    {
      Project     = var.name_prefix
      Scenario    = "vault-oracle-database-plugin"
      ManagedBy   = "terraform"
      Environment = "repro"
    },
    var.extra_tags,
  )

  vault_nodes = [
    {
      node_id      = "${var.name_prefix}-vault-1"
      subnet_index = 0
      private_ip   = cidrhost(var.subnet_cidrs[0], 10)
    },
    {
      node_id      = "${var.name_prefix}-vault-2"
      subnet_index = 1
      private_ip   = cidrhost(var.subnet_cidrs[1], 10)
    },
    {
      node_id      = "${var.name_prefix}-vault-3"
      subnet_index = 2
      private_ip   = cidrhost(var.subnet_cidrs[2], 10)
    },
  ]

  retry_join_blocks = join("\n", [
    for node in local.vault_nodes : <<-EOT
      retry_join {
        leader_api_addr = "http://${node.private_ip}:8200"
      }
    EOT
  ])
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "al2023" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

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
  count = 3

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-subnet-${count.index + 1}"
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
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "vault" {
  name        = "${var.name_prefix}-vault-sg"
  description = "Vault nodes for Oracle database plugin lab"
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

resource "aws_vpc_security_group_ingress_rule" "vault_api_cluster" {
  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.vault.id
  from_port                    = 8200
  ip_protocol                  = "tcp"
  to_port                      = 8200
  description                  = "Vault inter-node API access"
}

resource "aws_vpc_security_group_ingress_rule" "vault_cluster" {
  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.vault.id
  from_port                    = 8201
  ip_protocol                  = "tcp"
  to_port                      = 8201
  description                  = "Vault Raft cluster port"
}

resource "aws_vpc_security_group_egress_rule" "vault_all" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound access for package and binary downloads"
}

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
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
      ]
      Resource = aws_kms_key.vault_unseal.arn
    }]
  })
}

resource "aws_iam_instance_profile" "vault_node" {
  name = "${var.name_prefix}-vault-node"
  role = aws_iam_role.vault_node.name
}

resource "aws_instance" "vault" {
  count = length(local.vault_nodes)

  ami                         = coalesce(var.ami_id, one(data.aws_ami.al2023[*].image_id))
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public[local.vault_nodes[count.index].subnet_index].id
  private_ip                  = local.vault_nodes[count.index].private_ip
  vpc_security_group_ids      = [aws_security_group.vault.id]
  iam_instance_profile        = aws_iam_instance_profile.vault_node.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    aws_region                     = var.aws_region
    cluster_name                   = var.name_prefix
    kms_key_id                     = aws_kms_key.vault_unseal.key_id
    node_id                        = local.vault_nodes[count.index].node_id
    node_private_ip                = local.vault_nodes[count.index].private_ip
    oracle_instant_client_base_url = var.oracle_instant_client_base_url
    oracle_instant_client_version  = var.oracle_instant_client_version
    oracle_plugin_version          = trimprefix(var.oracle_plugin_version, "v")
    retry_join_blocks              = local.retry_join_blocks
    vault_license_b64              = base64encode(var.vault_license)
    vault_log_level                = var.vault_log_level
    vault_version                  = var.vault_version
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
    Name          = local.vault_nodes[count.index].node_id
    vault-cluster = var.name_prefix
    vault-node-id = local.vault_nodes[count.index].node_id
    vault-role    = "voter"
  }
}

resource "vault_plugin" "oracle" {
  count = var.register_oracle_plugin ? 1 : 0

  depends_on = [aws_instance.vault]

  type    = "database"
  name    = "vault-plugin-database-oracle"
  version = var.oracle_plugin_version
}

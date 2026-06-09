locals {
  common_tags = merge(
    {
      Project     = var.name_prefix
      Scenario    = "vault-pr-dr-replication"
      ManagedBy   = "terraform"
      Environment = "repro"
    },
    var.extra_tags,
  )

  # Primary cluster: one node per AZ, private IPs at host .10 in each subnet.
  primary_nodes = [
    {
      node_id      = "${var.name_prefix}-primary-1"
      subnet_index = 0
      private_ip   = cidrhost(var.subnet_cidrs[0], 10)
      cluster_name = "${var.name_prefix}-primary"
    },
    {
      node_id      = "${var.name_prefix}-primary-2"
      subnet_index = 1
      private_ip   = cidrhost(var.subnet_cidrs[1], 10)
      cluster_name = "${var.name_prefix}-primary"
    },
    {
      node_id      = "${var.name_prefix}-primary-3"
      subnet_index = 2
      private_ip   = cidrhost(var.subnet_cidrs[2], 10)
      cluster_name = "${var.name_prefix}-primary"
    },
  ]

  # Performance replication secondary cluster: host .20 in each subnet.
  pr_nodes = [
    {
      node_id      = "${var.name_prefix}-pr-1"
      subnet_index = 0
      private_ip   = cidrhost(var.subnet_cidrs[0], 20)
      cluster_name = "${var.name_prefix}-pr-secondary"
    },
    {
      node_id      = "${var.name_prefix}-pr-2"
      subnet_index = 1
      private_ip   = cidrhost(var.subnet_cidrs[1], 20)
      cluster_name = "${var.name_prefix}-pr-secondary"
    },
    {
      node_id      = "${var.name_prefix}-pr-3"
      subnet_index = 2
      private_ip   = cidrhost(var.subnet_cidrs[2], 20)
      cluster_name = "${var.name_prefix}-pr-secondary"
    },
  ]

  # DR secondary cluster: host .30 in each subnet.
  dr_nodes = [
    {
      node_id      = "${var.name_prefix}-dr-1"
      subnet_index = 0
      private_ip   = cidrhost(var.subnet_cidrs[0], 30)
      cluster_name = "${var.name_prefix}-dr-secondary"
    },
    {
      node_id      = "${var.name_prefix}-dr-2"
      subnet_index = 1
      private_ip   = cidrhost(var.subnet_cidrs[1], 30)
      cluster_name = "${var.name_prefix}-dr-secondary"
    },
    {
      node_id      = "${var.name_prefix}-dr-3"
      subnet_index = 2
      private_ip   = cidrhost(var.subnet_cidrs[2], 30)
      cluster_name = "${var.name_prefix}-dr-secondary"
    },
  ]

  primary_retry_join_blocks = join("\n", [
    for node in local.primary_nodes : <<-EOT
      retry_join {
        leader_api_addr = "http://${node.private_ip}:8200"
      }
    EOT
  ])

  pr_retry_join_blocks = join("\n", [
    for node in local.pr_nodes : <<-EOT
      retry_join {
        leader_api_addr = "http://${node.private_ip}:8200"
      }
    EOT
  ])

  dr_retry_join_blocks = join("\n", [
    for node in local.dr_nodes : <<-EOT
      retry_join {
        leader_api_addr = "http://${node.private_ip}:8200"
      }
    EOT
  ])
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "rhel8" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["309956199498"] # Red Hat, Inc.

  filter {
    name   = "name"
    values = ["RHEL-8.*_HVM-*-x86_64-*-Hourly2-GP3"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
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

# ─── Security Group ───────────────────────────────────────────────────────────

resource "aws_security_group" "vault" {
  name        = "${var.name_prefix}-vault-sg"
  description = "Vault nodes for PR and DR replication lab"
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

# All nine nodes (three clusters) share this security group so that the Vault
# API (8200) and cluster port (8201) are reachable across clusters for
# replication traffic without extra peering or security group rules.
resource "aws_vpc_security_group_ingress_rule" "vault_api_cluster" {
  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.vault.id
  from_port                    = 8200
  ip_protocol                  = "tcp"
  to_port                      = 8200
  description                  = "Vault inter-node API and replication access"
}

resource "aws_vpc_security_group_ingress_rule" "vault_cluster" {
  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.vault.id
  from_port                    = 8201
  ip_protocol                  = "tcp"
  to_port                      = 8201
  description                  = "Vault cluster and replication port"
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

# ─── EC2 Instances ────────────────────────────────────────────────────────────

resource "aws_instance" "primary" {
  count = length(local.primary_nodes)

  ami                         = coalesce(var.ami_id, one(data.aws_ami.rhel8[*].image_id))
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public[local.primary_nodes[count.index].subnet_index].id
  private_ip                  = local.primary_nodes[count.index].private_ip
  vpc_security_group_ids      = [aws_security_group.vault.id]
  iam_instance_profile        = aws_iam_instance_profile.vault_node.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    node_id           = local.primary_nodes[count.index].node_id
    node_private_ip   = local.primary_nodes[count.index].private_ip
    cluster_name      = local.primary_nodes[count.index].cluster_name
    vault_version     = var.vault_version
    vault_log_level   = var.vault_log_level
    retry_join_blocks = local.primary_retry_join_blocks
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
    Name          = local.primary_nodes[count.index].node_id
    vault-cluster = "${var.name_prefix}-primary"
    vault-node-id = local.primary_nodes[count.index].node_id
    vault-role    = "voter"
  }
}

resource "aws_instance" "pr_secondary" {
  count = length(local.pr_nodes)

  ami                         = coalesce(var.ami_id, one(data.aws_ami.rhel8[*].image_id))
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public[local.pr_nodes[count.index].subnet_index].id
  private_ip                  = local.pr_nodes[count.index].private_ip
  vpc_security_group_ids      = [aws_security_group.vault.id]
  iam_instance_profile        = aws_iam_instance_profile.vault_node.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    node_id           = local.pr_nodes[count.index].node_id
    node_private_ip   = local.pr_nodes[count.index].private_ip
    cluster_name      = local.pr_nodes[count.index].cluster_name
    vault_version     = var.vault_version
    vault_log_level   = var.vault_log_level
    retry_join_blocks = local.pr_retry_join_blocks
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
    Name          = local.pr_nodes[count.index].node_id
    vault-cluster = "${var.name_prefix}-pr-secondary"
    vault-node-id = local.pr_nodes[count.index].node_id
    vault-role    = "voter"
  }
}

resource "aws_instance" "dr_secondary" {
  count = length(local.dr_nodes)

  ami                         = coalesce(var.ami_id, one(data.aws_ami.rhel8[*].image_id))
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public[local.dr_nodes[count.index].subnet_index].id
  private_ip                  = local.dr_nodes[count.index].private_ip
  vpc_security_group_ids      = [aws_security_group.vault.id]
  iam_instance_profile        = aws_iam_instance_profile.vault_node.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    node_id           = local.dr_nodes[count.index].node_id
    node_private_ip   = local.dr_nodes[count.index].private_ip
    cluster_name      = local.dr_nodes[count.index].cluster_name
    vault_version     = var.vault_version
    vault_log_level   = var.vault_log_level
    retry_join_blocks = local.dr_retry_join_blocks
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
    Name          = local.dr_nodes[count.index].node_id
    vault-cluster = "${var.name_prefix}-dr-secondary"
    vault-node-id = local.dr_nodes[count.index].node_id
    vault-role    = "voter"
  }
}

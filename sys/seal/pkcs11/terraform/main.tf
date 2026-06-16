locals {
  common_tags = merge(
    {
      Project     = var.name_prefix
      Scenario    = "vault-cloudhsm-pkcs11-sealwrap-kv-latency"
      ManagedBy   = "terraform"
      Environment = "repro"
    },
    var.extra_tags,
  )

  vault_nodes = [
    for idx in range(var.vault_node_count) : {
      index        = idx
      node_id      = "vault-${idx + 1}"
      subnet_index = idx % 3
      private_ip   = cidrhost(var.subnet_cidrs[idx % 3], 10 + floor(idx / 3))
      role         = idx == 5 ? "non-voter" : "voter"
    }
  ]

  retry_join_blocks = join("\n", [
    for node in slice(local.vault_nodes, 0, 3) : <<-EOT
      retry_join {
        leader_api_addr = "http://${node.private_ip}:8200"
      }
    EOT
  ])
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "hc_base_al2023" {
  count = var.ami_id == null ? 1 : 0
  filter {
    name   = "name"
    values = [format("hc-base-al2023-%s-*", var.ami_architecture)]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  most_recent = true
  owners      = ["888995627335"] # ami-prod account
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
  description = "Vault nodes for CloudHSM PKCS11 latency reproduction"
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
  description                  = "Vault node API access"
}

resource "aws_vpc_security_group_ingress_rule" "vault_cluster" {
  security_group_id            = aws_security_group.vault.id
  referenced_security_group_id = aws_security_group.vault.id
  from_port                    = 8201
  ip_protocol                  = "tcp"
  to_port                      = 8201
  description                  = "Vault cluster traffic"
}

resource "aws_vpc_security_group_egress_rule" "vault_all" {
  security_group_id = aws_security_group.vault.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Outbound access for package downloads and CloudHSM"
}

resource "aws_cloudhsm_v2_cluster" "this" {
  hsm_type   = var.cloudhsm_hsm_type
  mode       = var.cloudhsm_mode
  subnet_ids = aws_subnet.public[*].id

  tags = {
    Name = "${var.name_prefix}-cloudhsm"
  }
}

resource "aws_cloudhsm_v2_hsm" "initial" {
  count = var.create_initial_hsm ? 1 : 0

  cluster_id = aws_cloudhsm_v2_cluster.this.cluster_id
  subnet_id  = aws_subnet.public[0].id
}

resource "aws_iam_role" "vault_node" {
  name = "${var.name_prefix}-vault-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "vault_cloudhsm_describe" {
  name = "${var.name_prefix}-cloudhsm-describe"
  role = aws_iam_role.vault_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudhsm:DescribeClusters",
          "cloudhsm:DescribeBackups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "vault_node" {
  name = "${var.name_prefix}-vault-node-profile"
  role = aws_iam_role.vault_node.name
}

resource "aws_instance" "vault" {
  count = var.vault_node_count

  ami                         = coalesce(var.ami_id, one(data.aws_ami.hc_base_al2023[*].image_id))
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.public[local.vault_nodes[count.index].subnet_index].id
  private_ip                  = local.vault_nodes[count.index].private_ip
  vpc_security_group_ids      = [aws_security_group.vault.id, aws_cloudhsm_v2_cluster.this.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.vault_node.name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    node_id                 = local.vault_nodes[count.index].node_id
    node_private_ip         = local.vault_nodes[count.index].private_ip
    vault_version           = var.vault_version
    vault_log_level         = var.vault_log_level
    hsm_user                = var.hsm_user
    hsm_password_b64        = base64encode(var.hsm_password)
    hsm_token_label         = var.hsm_token_label
    hsm_key_label           = var.hsm_key_label
    hsm_hmac_key_label      = var.hsm_hmac_key_label
    pkcs11_lib_path         = var.pkcs11_lib_path
    pkcs11_max_parallel     = var.pkcs11_max_parallel
    retry_join_blocks       = local.retry_join_blocks
    retry_join_as_non_voter = local.vault_nodes[count.index].role == "non-voter" ? "true" : "false"
    vault_license_b64       = base64encode(var.vault_license)
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
    Name          = "${var.name_prefix}-${local.vault_nodes[count.index].node_id}"
    vault-cluster = var.name_prefix
    vault-node-id = local.vault_nodes[count.index].node_id
    vault-role    = local.vault_nodes[count.index].role
  }

  depends_on = [aws_cloudhsm_v2_cluster.this]
}

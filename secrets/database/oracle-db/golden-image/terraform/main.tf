data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.86.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name_prefix }
}

resource "aws_subnet" "lab" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.86.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
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
  name_prefix = "${var.name_prefix}-"
  description = "Administrator SSH and private lab-member traffic"
  vpc_id      = aws_vpc.lab.id
}

resource "aws_vpc_security_group_ingress_rule" "members" {
  for_each                     = toset(["8200", "8201", "1521"])
  security_group_id            = aws_security_group.lab.id
  referenced_security_group_id = aws_security_group.lab.id
  ip_protocol                  = "tcp"
  from_port                    = tonumber(each.key)
  to_port                      = tonumber(each.key)
  description                  = "Private Vault API, Raft forwarding, or Oracle access between lab members"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.lab.id
  cidr_ipv4         = var.admin_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "outbound" {
  security_group_id = aws_security_group.lab.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_kms_key" "seal" {
  description             = "Auto-unseal for ${var.name_prefix}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "seal" {
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.seal.key_id
}

resource "aws_iam_role" "lab" {
  name_prefix = "${var.name_prefix}-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "seal" {
  role = aws_iam_role.lab.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"], Resource = aws_kms_key.seal.arn
    }]
  })
}

resource "aws_iam_instance_profile" "lab" {
  name_prefix = "${var.name_prefix}-"
  role        = aws_iam_role.lab.name
}

locals {
  nodes = [for index in range(var.vault_node_count) : {
    node_id    = "oracle-baseline-${index + 1}"
    private_ip = cidrhost(aws_subnet.lab.cidr_block, index + 10)
  }]
  # All nodes install identical plugin/client artifacts; only node 1 hosts Oracle
  # and initializes/populates the cluster. Addresses do not depend on instances.
  node_configs = [for index, node in local.nodes : {
    aws_region                     = var.aws_region
    kms_key_id                     = aws_kms_key.seal.key_id
    vault_version                  = var.vault_version
    oracle_plugin_version          = var.oracle_plugin_version
    static_role_count              = var.static_role_count
    dynamic_role_count             = var.dynamic_role_count
    static_rotation_period_seconds = var.static_rotation_period_seconds
    node_index                     = index
    node_id                        = node.node_id
    private_ip                     = node.private_ip
    nodes                          = local.nodes
    oracle_host                    = local.nodes[0].private_ip
  }]
  user_data = [for config in local.node_configs : templatefile("${path.module}/user-data.sh.tftpl", {
    config_b64    = base64encode(jsonencode(config))
    license_b64   = base64encode(var.vault_license)
    bootstrap_b64 = filebase64("${path.module}/../scripts/bootstrap.sh")
    configure_b64 = filebase64("${path.module}/../scripts/configure.sh")
    verify_b64    = filebase64("${path.module}/../scripts/verify.sh")
  })]
}

# Preserve the resource address when upgrading an existing single-node checkout.
moved {
  from = aws_instance.lab
  to   = aws_instance.lab[0]
}

resource "aws_instance" "lab" {
  count                       = var.vault_node_count
  ami                         = coalesce(var.ami_id, one(data.aws_ami.amazon_linux[*].id))
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.lab.id
  private_ip                  = local.nodes[count.index].private_ip
  vpc_security_group_ids      = [aws_security_group.lab.id]
  iam_instance_profile        = aws_iam_instance_profile.lab.name
  associate_public_ip_address = true
  user_data_base64            = base64gzip(local.user_data[count.index])
  user_data_replace_on_change = true
  depends_on                  = [aws_route_table_association.lab, aws_iam_role_policy.seal, aws_vpc_security_group_egress_rule.outbound, aws_vpc_security_group_ingress_rule.members]

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }
  metadata_options {
    http_tokens = "required"
  }
  lifecycle {
    precondition {
      condition     = contains(data.aws_ec2_instance_type.selected.supported_architectures, "x86_64") && data.aws_ec2_instance_type.selected.memory_size >= 8192
      error_message = "Oracle baseline requires an x86_64 instance with at least 8 GiB RAM."
    }
    precondition {
      condition     = length(base64gzip(local.user_data[count.index])) <= 21844
      error_message = "Compressed user data exceeds the EC2 16-KiB limit; reduce the bootstrap payload."
    }
  }
  tags = { Name = "${var.name_prefix}-${count.index + 1}" }
}

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
    name   = "state"
    values = ["available"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ec2_instance_type_offerings" "lab" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

locals {
  supported_azs = sort(tolist(setintersection(
    toset(data.aws_availability_zones.available.names),
    toset(data.aws_ec2_instance_type_offerings.lab.locations),
  )))
}

resource "aws_vpc" "lab" {
  cidr_block           = "10.62.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "lab" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.62.1.0/24"
  availability_zone       = length(local.supported_azs) > 0 ? local.supported_azs[0] : null
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name_prefix}-subnet" }

  lifecycle {
    precondition {
      condition     = length(local.supported_azs) > 0
      error_message = "The selected instance type is not offered in any available Availability Zone in the selected region."
    }
  }
}

resource "aws_route_table" "lab" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = { Name = "${var.name_prefix}-route" }
}

resource "aws_route_table_association" "lab" {
  subnet_id      = aws_subnet.lab.id
  route_table_id = aws_route_table.lab.id
}

resource "aws_security_group" "lab" {
  name        = "${var.name_prefix}-sg"
  description = "SSH-only disposable Oracle/Vault lab"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${var.name_prefix}-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.lab.id
  cidr_ipv4         = var.admin_ssh_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  description       = "Restricted SSH from the lab operator"
}

resource "aws_vpc_security_group_egress_rule" "downloads" {
  security_group_id = aws_security_group.lab.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Packages, Oracle image and Enterprise binaries"
}

resource "aws_instance" "lab" {
  depends_on = [aws_route_table_association.lab]

  ami                         = var.ami_id == null ? data.aws_ami.al2023[0].id : var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = aws_subnet.lab.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data_base64 = base64gzip(templatefile("${path.module}/user-data.sh.tftpl", {
    vault_version          = var.vault_version
    oracle_plugin_version  = var.oracle_plugin_version
    vault_license_b64      = base64encode(trimspace(var.vault_license))
    bootstrap_b64          = filebase64("${path.module}/bootstrap.sh")
    setup_b64              = filebase64("${path.module}/setup-lab.sh")
    candidate_register_b64 = filebase64("${path.module}/register-candidate.sh")
  }))

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = var.name_prefix }
}

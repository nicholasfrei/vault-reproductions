

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for the dedicated lab and KMS key."
}

variable "aws_profile" {
  type        = string
  default     = null
  description = "Optional local AWS profile; null uses the normal credential chain."
}

variable "name_prefix" {
  type    = string
  default = "oracle-rotation-lab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,35}$", var.name_prefix))
    error_message = "Use 3–36 lowercase letters, numbers, or hyphens, starting with a letter."
  }
}

variable "ami_owner" {
  type        = string
  default     = "888995627335"
  description = "Account that owns the base image (default: HashiCorp ami-prod). Use \"amazon\" in accounts that cannot see hc-base images."
}

variable "ami_name_pattern" {
  type        = string
  default     = "hc-base-al2023-x86_64-*"
  description = "Name filter for the base image; it must be Amazon Linux 2023 x86-64 (bootstrap.sh uses dnf and ec2-user)."
}

variable "instance_type" {
  type        = string
  default     = "t3.large"
  description = "Use an x86-64 instance with at least 8 GiB RAM for Oracle and Vault."
}

variable "root_volume_size" {
  type    = number
  default = 80
  validation {
    condition     = var.root_volume_size >= 50
    error_message = "Use at least 50 GiB for Oracle, packages, and evidence."
  }
}

variable "admin_ssh_cidr" {
  type        = string
  description = "IPv4 CIDR allowed to SSH to the lab instance."
  validation {
    condition     = can(cidrnetmask(var.admin_ssh_cidr))
    error_message = "admin_ssh_cidr must be an IPv4 CIDR."
  }
}

variable "key_name" {
  type        = string
  description = "Existing EC2 key pair name for SSH access."
}

variable "vault_version" {
  type        = string
  default     = "1.21.9+ent"
  description = "Vault Enterprise version installed by bootstrap.sh (read from /root/oracle-lab/vault-version)."
}

variable "plugin_version" {
  type        = string
  default     = "0.11.0+ent"
  description = "Oracle database plugin version registered by configure.sh (read from /root/oracle-lab/plugin-version)."
}

variable "vault_license" {
  type        = string
  sensitive   = true
  description = "Set TF_VAR_vault_license from your existing VAULT_LICENSE shell variable."
  validation {
    condition     = length(trimspace(var.vault_license)) > 0
    error_message = "An Enterprise license is required."
  }
}

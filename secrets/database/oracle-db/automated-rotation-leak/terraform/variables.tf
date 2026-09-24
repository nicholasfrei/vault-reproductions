

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

variable "ssh_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "IPv4 SSH access for the shared-password lab user."
  validation {
    condition     = can(cidrnetmask(var.ssh_cidr))
    error_message = "ssh_cidr must be an IPv4 CIDR."
  }
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

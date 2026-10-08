variable "aws_region" {
  description = "AWS region for the disposable lab."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+(-[a-z]+)?-[0-9]+$", var.aws_region))
    error_message = "Provide an AWS region name such as us-east-1."
  }
}

variable "aws_profile" {
  description = "Optional local AWS profile; null uses the default credential chain."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Unique prefix for lab resources."
  type        = string
  default     = "oracle-rotation-lab"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,27}$", var.name_prefix))
    error_message = "Use 2-28 lowercase letters, digits, and hyphens, starting with a letter."
  }
}

variable "key_name" {
  description = "Existing EC2 SSH key pair name."
  type        = string
}

variable "admin_ssh_cidr" {
  description = "Trusted workstation IPv4 CIDR allowed SSH access; do not use an unrestricted range."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_ssh_cidr)) && !endswith(var.admin_ssh_cidr, "/0")
    error_message = "Provide a restricted IPv4 CIDR for SSH access."
  }
}

variable "vault_license" {
  description = "Vault Enterprise license; set through TF_VAR_vault_license, not a tfvars file. The value is stored in Terraform state and EC2 user data."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.vault_license)) > 0
    error_message = "A Vault Enterprise license is required."
  }
}

variable "instance_type" {
  description = "An x86_64 instance with at least 8 GiB of memory is recommended for Oracle XE and Vault."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Encrypted root volume size in GiB; Oracle image and database need substantial space."
  type        = number
  default     = 60

  validation {
    condition     = var.root_volume_size >= 50
    error_message = "Allow at least 50 GiB for the Vault and Oracle images."
  }
}

variable "vault_version" {
  description = "Vault Enterprise Linux AMD64 release. Default matches the verified custom plugin test."
  type        = string
  default     = "2.1.1+ent"

  validation {
    condition     = can(regex("^[0-9]+[.][0-9]+[.][0-9]+[+]ent$", var.vault_version))
    error_message = "Use a Vault Enterprise release such as 2.1.1+ent."
  }
}

variable "oracle_plugin_version" {
  description = "Published Oracle Enterprise plugin release compatible with the selected Vault version."
  type        = string
  default     = "0.14.1+ent"

  validation {
    condition     = can(regex("^[0-9]+[.][0-9]+[.][0-9]+[+]ent$", var.oracle_plugin_version))
    error_message = "Use a published Oracle Enterprise plugin release such as 0.14.1+ent."
  }
}

variable "ami_id" {
  description = "Optional AMI ID override; null selects the latest hc-base-al2023 x86_64 AMI."
  type        = string
  default     = null
}

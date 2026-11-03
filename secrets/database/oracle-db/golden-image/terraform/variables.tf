variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  description = "Optional local AWS profile; null uses the standard credential chain."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Unique name for this lab in the selected account and region."
  type        = string
  default     = "oracle-baseline"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.name_prefix))
    error_message = "Use 3–30 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "key_name" {
  description = "Existing EC2 key pair in aws_region."
  type        = string
}

variable "admin_ssh_cidr" {
  description = "Trusted IPv4 source range for SSH, normally your current egress address /32."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.admin_ssh_cidr)) && try(tonumber(split("/", var.admin_ssh_cidr)[1]) >= 24, false)
    error_message = "Supply a valid IPv4 CIDR with prefix /24 through /32."
  }
}

variable "ami_id" {
  description = "Optional Amazon Linux 2023 x86_64 AMI; null discovers a public Amazon image. Pin for repeatable comparisons."
  type        = string
  default     = null
}

variable "instance_type" {
  type    = string
  default = "t3.large"
}

variable "vault_node_count" {
  description = "Vault Raft voters: one by default, or three when explicitly requested. Oracle runs on node 1 in either topology. Select before provisioning."
  type        = number
  default     = 1
  validation {
    condition     = contains([1, 3], var.vault_node_count)
    error_message = "vault_node_count must be 1 or 3."
  }
}

variable "root_volume_size" {
  description = "Encrypted gp3 disk in GiB, including Oracle image and persistent database data."
  type        = number
  default     = 80
  validation {
    condition     = var.root_volume_size >= 60 && floor(var.root_volume_size) == var.root_volume_size
    error_message = "Use an integer disk size of at least 60 GiB."
  }
}

variable "vault_license" {
  description = "Enterprise license, supplied with TF_VAR_vault_license; retained in state and EC2 user data."
  type        = string
  sensitive   = true
  validation {
    condition     = length(trimspace(var.vault_license)) > 0
    error_message = "Supply a nonempty Vault Enterprise license."
  }
}

variable "vault_version" {
  description = "Released Linux AMD64 Enterprise version. This baseline targets Vault 1.20+ with official packaged plugins."
  type        = string
  default     = "2.1.1+ent"
  validation {
    condition = can(regex("^[1-9][0-9]*\\.[0-9]+\\.[0-9]+\\+ent$", var.vault_version)) && try(
      tonumber(split(".", var.vault_version)[0]) > 1 || tonumber(split(".", var.vault_version)[1]) >= 20, false
    )
    error_message = "Use an Enterprise release such as 2.1.1+ent, with Vault 1.20 or later."
  }
}

variable "oracle_plugin_version" {
  description = "Released Enterprise Oracle plugin version, without a leading v. Compatibility is checked during bootstrap."
  type        = string
  default     = "0.14.1+ent"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\+ent$", var.oracle_plugin_version))
    error_message = "Use a released plugin version such as 0.14.1+ent."
  }
}

variable "static_role_count" {
  description = "Pre-created Oracle users and corresponding Vault static roles."
  type        = number
  default     = 100
  validation {
    condition     = var.static_role_count >= 1 && var.static_role_count <= 1000 && floor(var.static_role_count) == var.static_role_count
    error_message = "Use an integer static-role count from 1 to 1000."
  }
}

variable "dynamic_role_count" {
  description = "Vault dynamic-role definitions. Oracle users are created when credentials are requested."
  type        = number
  default     = 100
  validation {
    condition     = var.dynamic_role_count >= 1 && var.dynamic_role_count <= 1000 && floor(var.dynamic_role_count) == var.dynamic_role_count
    error_message = "Use an integer dynamic-role count from 1 to 1000."
  }
}

variable "static_rotation_period_seconds" {
  type    = number
  default = 86400
  validation {
    condition     = var.static_rotation_period_seconds >= 60 && floor(var.static_rotation_period_seconds) == var.static_rotation_period_seconds
    error_message = "Use an integer rotation period of at least 60 seconds."
  }
}

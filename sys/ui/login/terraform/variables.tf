variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional AWS shared config profile. Leave null to use the default credential chain."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix used for resource names and EC2 Name tags."
  type        = string
  default     = "vault-ui-login-repro"
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH access."
  type        = string
}

variable "admin_ssh_cidr" {
  description = "CIDR allowed to SSH to all instances (for example your public IP as <ip>/32)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for each Vault node."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 30
}

variable "vault_version" {
  description = "Vault Enterprise version to install, including the +ent suffix (for example 1.20.9+ent)."
  type        = string
  default     = "1.20.9+ent"
}

variable "vault_license" {
  description = "Vault Enterprise license text. Prefer TF_VAR_vault_license in the shell instead of committing this value."
  type        = string
  sensitive   = true
}

variable "extra_tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}

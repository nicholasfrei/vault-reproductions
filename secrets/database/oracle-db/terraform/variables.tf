variable "aws_region" {
  description = "AWS region for the Oracle database secrets engine lab."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional AWS shared config profile. Leave null to use the default credential chain."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix used for AWS resource names, tags, and the Vault cluster name."
  type        = string
  default     = "vault-oracle-lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "subnet_cidrs" {
  description = "Three public subnet CIDR blocks, one per availability zone."
  type        = list(string)
  default     = ["10.42.10.0/24", "10.42.20.0/24", "10.42.30.0/24"]

  validation {
    condition     = length(var.subnet_cidrs) == 3
    error_message = "subnet_cidrs must contain exactly three CIDR blocks."
  }
}

variable "admin_ssh_cidr" {
  description = "CIDR allowed to SSH to Vault nodes and reach the Vault API on port 8200."
  type        = string
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH access."
  type        = string
}

variable "ami_id" {
  description = "Optional Amazon Linux 2023 AMI ID override. Leave null to auto-resolve the latest x86_64 AL2023 AMI."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 instance type for all Vault nodes."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB for each Vault node."
  type        = number
  default     = 30
}

variable "vault_version" {
  description = "Vault Enterprise version to install, including the +ent suffix."
  type        = string
  default     = "1.20.2+ent"
}

variable "vault_license" {
  description = "Vault Enterprise license text. Prefer setting TF_VAR_vault_license in the shell instead of committing this value."
  type        = string
  sensitive   = true
}

variable "vault_log_level" {
  description = "Vault server log level."
  type        = string
  default     = "info"
}

variable "oracle_instant_client_version" {
  description = "Oracle Instant Client directory suffix used by the download URLs."
  type        = string
  default     = "19_28"
}

variable "oracle_instant_client_base_url" {
  description = "Base URL for Oracle Instant Client downloads."
  type        = string
  default     = "https://download.oracle.com/otn_software/linux/instantclient/1928000"
}

variable "oracle_plugin_version" {
  description = "Oracle database plugin version to register in Vault. Include the leading v expected by Vault provider."
  type        = string
  default     = "v0.14.1+ent"
}

variable "register_oracle_plugin" {
  description = "Set to true after Vault is initialized and vault_addr/vault_token are available."
  type        = bool
  default     = false
}

variable "vault_addr" {
  description = "Vault API address used by the Vault provider after the cluster is initialized, for example http://<node_public_ip>:8200."
  type        = string
  default     = null
}

variable "vault_token" {
  description = "Vault token used by the Vault provider to register the Oracle database plugin after initialization."
  type        = string
  sensitive   = true
  default     = null
}

variable "extra_tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}

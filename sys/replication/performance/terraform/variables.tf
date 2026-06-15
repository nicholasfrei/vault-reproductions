variable "aws_region" {
  description = "AWS region for the lab."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional AWS shared config profile. Leave null to use the default credential chain."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix used for AWS resource names, tags, and Vault cluster names."
  type        = string
  default     = "vault-pr-lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  description = "Three public subnet CIDR blocks, one per availability zone."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]

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
  description = "Optional AMI ID override. Leave null to auto-resolve the latest RHEL 8 x86_64 AMI via AWS Marketplace SSM parameter."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "EC2 instance type for all Vault nodes."
  type        = string
  default     = "m6i.large"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB for each Vault node."
  type        = number
  default     = 40
}

variable "vault_version" {
  description = "Vault Enterprise version to install. Do not include the +ent suffix."
  type        = string
  default     = "1.19.6"
}

variable "vault_license" {
  description = "Vault Enterprise license text. Prefer setting TF_VAR_vault_license in the shell instead of committing this value."
  type        = string
  sensitive   = true
}

variable "vault_log_level" {
  description = "Vault server log level."
  type        = string
  default     = "trace"
}

variable "extra_tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}

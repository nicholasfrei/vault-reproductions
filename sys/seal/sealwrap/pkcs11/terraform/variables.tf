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
  description = "Prefix used for AWS resource names and tags."
  type        = string
  default     = "vault-hsm-deadlock"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "subnet_cidrs" {
  description = "Three subnet CIDR blocks, one per availability zone."
  type        = list(string)
  default     = ["10.42.10.0/24", "10.42.20.0/24", "10.42.30.0/24"]

  validation {
    condition     = length(var.subnet_cidrs) == 3
    error_message = "subnet_cidrs must contain exactly three CIDR blocks."
  }
}

variable "admin_ssh_cidr" {
  description = "CIDR allowed to SSH to Vault nodes and reach Vault API port 8200."
  type        = string
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH access."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Vault nodes."
  type        = string
  default     = "m6i.large"
}

variable "vault_version" {
  description = "Vault Enterprise version to install. Do not include +ent."
  type        = string
  default     = "1.19.15"
}

variable "vault_license" {
  description = "Vault Enterprise license text. Prefer TF_VAR_vault_license or terraform.tfvars that is not committed."
  type        = string
  sensitive   = true
}

variable "hsm_user" {
  description = "CloudHSM crypto user that Vault will use after you create it during CloudHSM activation."
  type        = string
  default     = "vault_user"
}

variable "hsm_password" {
  description = "CloudHSM crypto user password. Prefer TF_VAR_hsm_password or terraform.tfvars that is not committed."
  type        = string
  sensitive   = true
}

variable "hsm_token_label" {
  description = "CloudHSM token label for the PKCS11 seal. Unused with slot-based configuration but kept for reference."
  type        = string
  default     = "cavium"
}

variable "hsm_key_label" {
  description = "PKCS11 seal encryption key label."
  type        = string
  default     = "vault-hsm-key"
}

variable "hsm_hmac_key_label" {
  description = "PKCS11 seal HMAC key label."
  type        = string
  default     = "vault-hsm-hmac-key"
}

variable "pkcs11_lib_path" {
  description = "Path to the AWS CloudHSM PKCS11 shared library on Vault nodes."
  type        = string
  default     = "/opt/cloudhsm/lib/libcloudhsm_pkcs11.so"
}

variable "pkcs11_max_parallel" {
  description = "Vault PKCS11 seal max_parallel value."
  type        = number
  default     = 1
}

variable "vault_log_level" {
  description = "Vault server log level."
  type        = string
  default     = "trace"
}

variable "ami_id" {
  description = "Optional AMI ID. Leave null to use the latest Amazon Linux 2023 x86_64 AMI."
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB for each Vault node."
  type        = number
  default     = 40
}

variable "vault_node_count" {
  description = "Number of Vault EC2 nodes. Keep at 6 for this reproduction."
  type        = number
  default     = 6

  validation {
    condition     = var.vault_node_count == 6
    error_message = "This reproduction expects exactly six Vault nodes."
  }
}

variable "cloudhsm_hsm_type" {
  description = "AWS CloudHSM HSM type."
  type        = string
  default     = "hsm2m.medium"
}

variable "cloudhsm_mode" {
  description = "CloudHSM cluster mode. Required for hsm2m.medium. Valid values: FIPS, NON_FIPS."
  type        = string
  default     = "NON_FIPS"

  validation {
    condition     = contains(["FIPS", "NON_FIPS"], var.cloudhsm_mode)
    error_message = "cloudhsm_mode must be FIPS or NON_FIPS."
  }
}

variable "create_initial_hsm" {
  description = "Create one initial HSM in the first subnet."
  type        = bool
  default     = true
}

variable "extra_tags" {
  description = "Additional tags to apply to all taggable resources."
  type        = map(string)
  default     = {}
}

output "vpc_id" {
  description = "Lab VPC ID."
  value       = aws_vpc.this.id
}

output "subnet_id" {
  description = "Lab subnet ID."
  value       = aws_subnet.public.id
}

output "vault_security_group_id" {
  description = "Security group ID for the Vault node."
  value       = aws_security_group.vault.id
}

output "vault_node" {
  description = "Vault node addresses."
  value = {
    instance_id = aws_instance.vault.id
    private_ip  = aws_instance.vault.private_ip
    public_ip   = aws_instance.vault.public_ip
  }
}

output "ssh_command" {
  description = "Example SSH command for the Vault node."
  value       = "ssh ec2-user@${aws_instance.vault.public_ip}"
}

output "vault_addr" {
  description = "Vault API address (reachable from your admin CIDR)."
  value       = "http://${aws_instance.vault.public_ip}:8200"
}

output "kms_key_id" {
  description = "KMS key ID used for Vault auto-unseal."
  value       = aws_kms_key.vault_unseal.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN used for Vault auto-unseal."
  value       = aws_kms_key.vault_unseal.arn
}

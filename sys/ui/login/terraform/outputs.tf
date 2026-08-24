output "kms_key_id" {
  description = "KMS key ID used for Vault auto-unseal."
  value       = aws_kms_key.vault_unseal.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN used for Vault auto-unseal."
  value       = aws_kms_key.vault_unseal.arn
}

output "kms_alias" {
  description = "KMS key alias."
  value       = aws_kms_alias.vault_unseal.name
}

output "instance_ids" {
  description = "EC2 instance IDs for each Vault node."
  value       = { for k, v in aws_instance.vault : v.tags["Name"] => v.id }
}

output "public_ips" {
  description = "Public IP addresses for each Vault node."
  value       = { for k, v in aws_instance.vault : v.tags["Name"] => v.public_ip }
}

output "private_ips" {
  description = "Private IP addresses for each Vault node."
  value       = { for k, v in aws_instance.vault : v.tags["Name"] => v.private_ip }
}

output "vault_1_public_ip" {
  description = "Public IP of vault-1 (use this for initial operations)."
  value       = aws_instance.vault["1"].public_ip
}

output "ssh_commands" {
  description = "SSH commands for each node."
  value       = { for k, v in aws_instance.vault : v.tags["Name"] => "ssh -i <path-to-key.pem> ec2-user@${v.public_ip}" }
}

output "vault_addr_node1" {
  description = "Vault API address for vault-1."
  value       = "http://${aws_instance.vault["1"].public_ip}:8200"
}

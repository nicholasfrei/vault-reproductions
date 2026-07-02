output "vpc_id" {
  description = "Lab VPC ID."
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "Lab subnet IDs."
  value       = aws_subnet.public[*].id
}

output "vault_security_group_id" {
  description = "Security group ID shared by all Vault nodes."
  value       = aws_security_group.vault.id
}

output "vault_nodes" {
  description = "Vault node addresses."
  value = {
    for idx, instance in aws_instance.vault : local.vault_nodes[idx].node_id => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      vault_addr  = "http://${instance.public_ip}:8200"
    }
  }
}

output "ssh_commands" {
  description = "Example SSH commands for the Vault nodes."
  value = {
    for idx, instance in aws_instance.vault :
    local.vault_nodes[idx].node_id => "ssh ec2-user@${instance.public_ip}"
  }
}

output "kms_key_id" {
  description = "KMS key ID used for Vault auto-unseal."
  value       = aws_kms_key.vault_unseal.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN used for Vault auto-unseal."
  value       = aws_kms_key.vault_unseal.arn
}

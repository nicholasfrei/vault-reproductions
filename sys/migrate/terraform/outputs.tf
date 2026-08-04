output "vpc_id" {
  description = "Lab VPC ID."
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "Lab subnet IDs."
  value       = aws_subnet.public[*].id
}

output "vault_security_group_id" {
  description = "Security group ID for the Vault nodes."
  value       = aws_security_group.vault.id
}

output "postgres_security_group_id" {
  description = "Security group ID for the PostgreSQL node."
  value       = aws_security_group.postgres.id
}

output "postgres_node" {
  description = "PostgreSQL node addresses."
  value = {
    instance_id = aws_instance.postgres.id
    private_ip  = aws_instance.postgres.private_ip
    public_ip   = aws_instance.postgres.public_ip
    ssh         = "ssh ec2-user@${aws_instance.postgres.public_ip}"
  }
}

output "vault_nodes" {
  description = "Vault node addresses."
  value = {
    for idx, instance in aws_instance.vault : local.vault_nodes[idx].node_id => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      ssh         = "ssh ec2-user@${instance.public_ip}"
    }
  }
}

output "vault_api_addr" {
  description = "Vault API address on node-1 (use from the instance itself or via SSH tunnel)."
  value       = "http://${local.vault_nodes[0].private_ip}:8200"
}

output "kms_key_id" {
  description = "KMS key ID used for Vault auto-unseal."
  value       = aws_kms_key.vault_unseal.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN used for Vault auto-unseal."
  value       = aws_kms_key.vault_unseal.arn
}

output "postgres_connection_url" {
  description = "PostgreSQL connection URL used in the Vault storage stanza and migration config."
  value       = local.postgres_connection_url
  sensitive   = true
}

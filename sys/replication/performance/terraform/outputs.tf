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

output "primary_nodes" {
  description = "Primary cluster node addresses."
  value = {
    for idx, instance in aws_instance.primary : local.primary_nodes[idx].node_id => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
    }
  }
}

output "pr_secondary_nodes" {
  description = "Performance replication secondary cluster node addresses."
  value = {
    for idx, instance in aws_instance.pr_secondary : local.pr_nodes[idx].node_id => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
    }
  }
}

output "dr_secondary_nodes" {
  description = "DR secondary cluster node addresses."
  value = {
    for idx, instance in aws_instance.dr_secondary : local.dr_nodes[idx].node_id => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
    }
  }
}

output "ssh_commands" {
  description = "Example SSH commands for all nodes, grouped by cluster."
  value = {
    primary = {
      for idx, instance in aws_instance.primary :
      local.primary_nodes[idx].node_id => "ssh ec2-user@${instance.public_ip}"
    }
    pr_secondary = {
      for idx, instance in aws_instance.pr_secondary :
      local.pr_nodes[idx].node_id => "ssh ec2-user@${instance.public_ip}"
    }
    dr_secondary = {
      for idx, instance in aws_instance.dr_secondary :
      local.dr_nodes[idx].node_id => "ssh ec2-user@${instance.public_ip}"
    }
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

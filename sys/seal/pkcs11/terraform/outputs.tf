output "vpc_id" {
  description = "Lab VPC ID."
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "Lab subnet IDs."
  value       = aws_subnet.public[*].id
}

output "vault_security_group_id" {
  description = "Vault node security group ID."
  value       = aws_security_group.vault.id
}

output "cloudhsm_cluster_id" {
  description = "CloudHSM cluster ID."
  value       = aws_cloudhsm_v2_cluster.this.cluster_id
}

output "cloudhsm_security_group_id" {
  description = "CloudHSM security group ID."
  value       = aws_cloudhsm_v2_cluster.this.security_group_id
}

output "vault_nodes" {
  description = "Vault node addresses and intended Raft roles."
  value = {
    for idx, instance in aws_instance.vault : "vault-${idx + 1}" => {
      instance_id = instance.id
      private_ip  = instance.private_ip
      public_ip   = instance.public_ip
      role        = idx == 5 ? "non-voter" : "voter"
    }
  }
}

output "ssh_commands" {
  description = "Example SSH commands for each Vault node."
  value = {
    for idx, instance in aws_instance.vault : "vault-${idx + 1}" => "ssh ec2-user@${instance.public_ip}"
  }
}

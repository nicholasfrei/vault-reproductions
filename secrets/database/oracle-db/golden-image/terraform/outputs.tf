output "instance_id" {
  description = "Node 1, which owns Oracle and cluster initialization."
  value       = aws_instance.lab[0].id
}

output "instance_public_ip" {
  description = "Node 1 SSH endpoint. Application ports are restricted to lab members."
  value       = aws_instance.lab[0].public_ip
}

output "ami_id" {
  description = "Record this image ID when comparing versions."
  value       = aws_instance.lab[0].ami
}

output "vault_nodes" {
  description = "SSH endpoints and private Raft addresses for each node; readiness is checked on node 1."
  value = { for index, instance in aws_instance.lab : local.nodes[index].node_id => {
    instance_id  = instance.id
    public_ip    = instance.public_ip
    private_ip   = instance.private_ip
    hosts_oracle = index == 0
  } }
}

output "baseline" {
  description = "Requested configuration, not proof that guest bootstrap finished."
  value = {
    vault_version         = var.vault_version
    oracle_plugin_version = var.oracle_plugin_version
    vault_node_count      = var.vault_node_count
    static_roles          = var.static_role_count
    dynamic_roles         = var.dynamic_role_count
    mount                 = "oracle-db"
    connection            = "oracle"
  }
}

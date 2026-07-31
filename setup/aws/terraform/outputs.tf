output "vpc_id" {
  description = "Default VPC ID used for the instance."
  value       = data.aws_vpc.default.id
}

output "subnet_id" {
  description = "Subnet ID for the instance."
  value       = data.aws_subnet.default.id
}

output "security_group_id" {
  description = "Security group ID for the instance."
  value       = aws_security_group.vault.id
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.vault.id
}

output "public_ip" {
  description = "Public IPv4 address of the instance."
  value       = aws_instance.vault.public_ip
}

output "ssh_command" {
  description = "Example SSH command (replace with your private key path)."
  value       = "ssh -i <path-to-key.pem> ec2-user@${aws_instance.vault.public_ip}"
}

output "vault_addr_local" {
  description = "Vault API address on the instance (dev mode, HTTP)."
  value       = "http://127.0.0.1:8200"
}

output "vault_logs_hint" {
  description = "How to view Vault server output after SSH."
  value       = "cat /var/log/vault.log"
}

output "instance_id" {
  description = "Disposable lab VM for verification and teardown."
  value       = aws_instance.lab.id
}

output "instance_public_ip" {
  description = "Use only for SSH from the trusted CIDR; Vault and Oracle bind to loopback."
  value       = aws_instance.lab.public_ip
}

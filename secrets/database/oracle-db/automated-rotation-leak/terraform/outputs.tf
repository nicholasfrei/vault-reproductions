

output "instance_id" {
  value = aws_instance.lab.id
}

output "public_ip" {
  value = aws_instance.lab.public_ip
}

output "ssh_command" {
  value = "ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no lab@${aws_instance.lab.public_ip}"
}

output "ssh_password" {
  value     = random_password.ssh.result
  sensitive = true
}

output "kms_key_id" {
  value = aws_kms_key.unseal.key_id
}

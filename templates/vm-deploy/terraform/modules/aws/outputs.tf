output "ip" {
  description = "Public IP of the VM"
  value       = aws_instance.vm.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh nixos@${aws_instance.vm.public_ip}"
}

output "image_name" {
  description = "Name of the AMI that was created"
  value       = aws_ami.nixos.name
}

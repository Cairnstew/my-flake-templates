output "ip" {
  description = "Public IP of the VM"
  value       = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

output "ssh_command" {
  description = "SSH command to connect to the VM"
  value       = "ssh nixos@${google_compute_instance.vm.network_interface[0].access_config[0].nat_ip}"
}

output "image_name" {
  description = "Name of the GCE image that was created"
  value       = google_compute_image.nixos.name
}

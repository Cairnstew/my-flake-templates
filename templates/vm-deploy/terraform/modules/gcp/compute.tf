# VM instance
resource "google_compute_instance" "vm" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = google_compute_image.nixos.self_link
      size  = 20
    }
  }

  network_interface {
    network = data.google_compute_network.default.name
    access_config {}
  }

  metadata = {
    enable-oslogin = "FALSE"
    ssh-keys       = "nixos:${var.ssh_public_key}"
  }

  tags = ["nixos", var.vm_name]
}

# Firewall: SSH only
resource "google_compute_firewall" "ssh" {
  name    = "allow-ssh-${var.vm_name}"
  network = data.google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  target_tags   = [var.vm_name]
  source_ranges = ["0.0.0.0/0"]
}

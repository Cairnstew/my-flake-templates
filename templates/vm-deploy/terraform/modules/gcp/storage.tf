# GCS bucket to store images
resource "google_storage_bucket" "images" {
  name                        = var.bucket
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  lifecycle {
    ignore_changes = [name]
  }
}

# Upload the .tar.gz built by nix
resource "google_storage_bucket_object" "nixos_image" {
  name   = "nixos-${var.image_hash}.tar.gz"
  source = var.image_path
  bucket = google_storage_bucket.images.name
}

# Register it as a GCE image
resource "google_compute_image" "nixos" {
  name   = "nixos-${var.image_hash}"
  family = "nixos"

  raw_disk {
    source = google_storage_bucket_object.nixos_image.self_link
  }

  guest_os_features {
    type = "VIRTIO_SCSI_MULTIQUEUE"
  }

  lifecycle {
    create_before_destroy = true
  }
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "ccws-coursework-1-tfstate"
    prefix = "nixos-vm/gcp"
  }
}

module "gcp" {
  source = "../../modules/gcp"

  project        = var.project
  bucket         = var.bucket
  region         = var.region
  zone           = var.zone
  image_path     = var.image_path
  image_hash     = var.image_hash
  ssh_public_key = var.ssh_public_key
  vm_name        = var.vm_name
  machine_type   = var.machine_type
}

output "ip"          { value = module.gcp.ip }
output "ssh_command" { value = module.gcp.ssh_command }
output "image_name"  { value = module.gcp.image_name }

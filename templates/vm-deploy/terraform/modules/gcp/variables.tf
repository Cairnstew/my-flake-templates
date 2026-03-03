variable "project" {
  type        = string
  description = "GCP project ID"
}

variable "bucket" {
  type        = string
  description = "GCS bucket name for storing NixOS images"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "GCP region"
}

variable "zone" {
  type        = string
  default     = "us-central1-a"
  description = "GCP zone"
}

variable "image_path" {
  type        = string
  description = "Local path to the .tar.gz image built by nix"
}

variable "image_hash" {
  type        = string
  description = "Short git SHA used to name the GCE image"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for the nixos user"
}

variable "vm_name" {
  type        = string
  default     = "myvm"
  description = "Name of the GCE VM instance"
}

variable "machine_type" {
  type        = string
  default     = "e2-small"
  description = "GCE machine type"
}

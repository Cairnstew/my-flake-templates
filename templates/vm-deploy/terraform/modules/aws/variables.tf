variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "bucket" {
  type        = string
  description = "S3 bucket name for storing NixOS images"
}

variable "image_path" {
  type        = string
  description = "Local path to the .vhd or raw image built by nix (amazon format)"
}

variable "image_hash" {
  type        = string
  description = "Short git SHA used to name the AMI"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for the nixos user"
}

variable "vm_name" {
  type        = string
  default     = "myvm"
  description = "Name tag for the EC2 instance"
}

variable "instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 instance type"
}

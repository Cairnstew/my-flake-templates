variable "project"        { type = string }
variable "bucket"         { type = string }
variable "region"         { type = string; default = "us-central1" }
variable "zone"           { type = string; default = "us-central1-a" }
variable "image_path"     { type = string }
variable "image_hash"     { type = string }
variable "ssh_public_key" { type = string }
variable "vm_name"        { type = string; default = "myvm" }
variable "machine_type"   { type = string; default = "e2-small" }

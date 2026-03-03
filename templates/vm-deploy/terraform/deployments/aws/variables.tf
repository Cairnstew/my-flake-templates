variable "bucket"         { type = string }
variable "region"         { type = string; default = "us-east-1" }
variable "image_path"     { type = string }
variable "image_hash"     { type = string }
variable "ssh_public_key" { type = string }
variable "vm_name"        { type = string; default = "myvm" }
variable "instance_type"  { type = string; default = "t3.small" }

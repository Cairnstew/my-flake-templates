terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # S3 backend — create this bucket manually once before first apply:
  #   aws s3api create-bucket --bucket <your-tfstate-bucket> --region us-east-1
  backend "s3" {
    bucket = "ccws-coursework-1-tfstate-aws"
    key    = "nixos-vm/aws/terraform.tfstate"
    region = "us-east-1"
  }
}

module "aws" {
  source = "../../modules/aws"

  bucket         = var.bucket
  region         = var.region
  image_path     = var.image_path
  image_hash     = var.image_hash
  ssh_public_key = var.ssh_public_key
  vm_name        = var.vm_name
  instance_type  = var.instance_type
}

output "ip"          { value = module.aws.ip }
output "ssh_command" { value = module.aws.ssh_command }
output "image_name"  { value = module.aws.image_name }

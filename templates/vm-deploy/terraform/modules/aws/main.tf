provider "aws" {
  region = var.region
}

# Look up default VPC
data "aws_vpc" "default" {
  default = true
}

# Look up a public subnet in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

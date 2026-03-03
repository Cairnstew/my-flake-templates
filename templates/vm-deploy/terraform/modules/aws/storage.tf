# S3 bucket to store images
resource "aws_s3_bucket" "images" {
  bucket        = var.bucket
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload the image built by nix (use nixos-generators with format = "amazon")
resource "aws_s3_object" "nixos_image" {
  bucket = aws_s3_bucket.images.id
  key    = "nixos-${var.image_hash}.vhd"
  source = var.image_path
}

# Grant EC2 permission to import from S3
data "aws_iam_policy_document" "vmimport_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vmie.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vmimport" {
  name               = "vmimport-nixos-${var.image_hash}"
  assume_role_policy = data.aws_iam_policy_document.vmimport_assume.json
}

data "aws_iam_policy_document" "vmimport_policy" {
  statement {
    actions   = ["s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.images.arn, "${aws_s3_bucket.images.arn}/*"]
  }
  statement {
    actions   = ["ec2:ModifySnapshotAttribute", "ec2:CopySnapshot", "ec2:RegisterImage", "ec2:Describe*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vmimport" {
  role   = aws_iam_role.vmimport.id
  policy = data.aws_iam_policy_document.vmimport_policy.json
}

# Import the uploaded image as an EBS snapshot, then register as AMI
resource "aws_ebs_snapshot_import" "nixos" {
  disk_container {
    format = "VHD"
    user_bucket {
      s3_bucket = aws_s3_bucket.images.id
      s3_key    = aws_s3_object.nixos_image.key
    }
  }

  role_name = aws_iam_role.vmimport.name

  tags = {
    Name = "nixos-${var.image_hash}"
  }
}

resource "aws_ami" "nixos" {
  name                = "nixos-${var.image_hash}"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  architecture        = "x86_64"

  ebs_block_device {
    device_name = "/dev/xvda"
    snapshot_id = aws_ebs_snapshot_import.nixos.id
    volume_size = 20
    volume_type = "gp3"
  }

  lifecycle {
    create_before_destroy = true
  }
}

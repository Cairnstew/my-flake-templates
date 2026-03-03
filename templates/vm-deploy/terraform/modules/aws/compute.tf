# SSH key pair
resource "aws_key_pair" "nixos" {
  key_name   = "nixos-${var.vm_name}"
  public_key = var.ssh_public_key
}

# Security group: SSH only
resource "aws_security_group" "ssh" {
  name        = "allow-ssh-${var.vm_name}"
  description = "Allow SSH inbound"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance
resource "aws_instance" "vm" {
  ami                         = aws_ami.nixos.id
  instance_type               = var.instance_type
  subnet_id                   = tolist(data.aws_subnets.default.ids)[0]
  key_name                    = aws_key_pair.nixos.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = var.vm_name
  }
}

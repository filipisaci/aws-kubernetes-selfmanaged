terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "sa-east-1"
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_key_pair" "generated_key" {
  key_name   = "terraform-ssh-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  filename        = "terraform-ssh-key.pem"
  content         = tls_private_key.ssh.private_key_pem
  file_permission = "0400"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["099720109477"]
}

resource "aws_vpc" "minha_vpc" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "minha_vpc"
  }
}

resource "aws_subnet" "minha_subnet" {
  vpc_id                  = aws_vpc.minha_vpc.id
  cidr_block              = "172.16.10.0/24"
  availability_zone       = "sa-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "minha_subnet"
  }
}

resource "aws_subnet" "minha_subnet_b" {
  vpc_id                  = aws_vpc.minha_vpc.id
  cidr_block              = "172.16.20.0/24"
  availability_zone       = "sa-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "minha_subnet_b"
  }
}

resource "aws_security_group" "inbound_rules" {
  name        = "inbound_allow"
  description = "Allow inbound traffic"
  vpc_id      = aws_vpc.minha_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["191.240.174.3/32"]
    description = "Filipi Home"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP to EC2"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to EC2"
  }

  # Permitir tráfego entre instâncias do mesmo SG
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Permitir trafego interno entre instancias"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "k8s"
  }
}

resource "aws_instance" "ec2" {
  count                  = 3
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.generated_key.key_name
  subnet_id              = aws_subnet.minha_subnet.id
  vpc_security_group_ids = [aws_security_group.inbound_rules.id]
  availability_zone      = "sa-east-1a"

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 16
    delete_on_termination = true
    encrypted             = true
    tags = {
      Name   = "SO"
      backup = "true"
    }
  }


  tags = {
    Name   = "k8s-${count.index + 1}"
    backup = "true"
  }
}

resource "aws_ebs_volume" "permanent_disk" {
  count             = 2
  size              = 16
  type              = "gp3"
  availability_zone = "sa-east-1a"

  tags = {
    Name   = "k8s-data-${count.index + 1}"
    backup = "true"
  }
}

resource "aws_volume_attachment" "attachment" {
  count       = 2
  volume_id   = aws_ebs_volume.permanent_disk[count.index].id
  instance_id = aws_instance.ec2[count.index].id
  device_name = "/dev/sdf"
  depends_on  = [aws_instance.ec2]
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.minha_vpc.id

  tags = {
    Name = "internet-gateway"
  }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.minha_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "route-table"
  }
}

resource "aws_route_table_association" "rta" {
  subnet_id      = aws_subnet.minha_subnet.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_dlm_lifecycle_policy" "backup_policy" {
  description = "Politica de Snapshot para discos EBS"
  #execution_role_arn = aws_iam_role.dlm_lifecycle_role.arn
  execution_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AWSDataLifecycleManagerDefaultRole"
  state              = "ENABLED"

  policy_details {
    resource_types = ["INSTANCE"]

    schedule {
      name = "Agendamento diario"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["23:45"]
      }

      retain_rule {
        count = 3
      }

      tags_to_add = {
        SnapshotCreator = "DLM"
      }

      copy_tags = true
    }

    target_tags = {
      backup = "true"
    }
  }
}

data "aws_caller_identity" "current" {}

output "instance_public_ips" {
  description = "IPs públicos das instâncias EC2"
  value       = [for instance in aws_instance.ec2 : instance.public_ip]
}

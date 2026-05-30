provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Course    = "CS312"
      Project   = "Course Project 2"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "minecraft" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cs312-course-project-2-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.minecraft.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1c"
  map_public_ip_on_launch = true

  tags = {
    Name = "cs312-course-project-2-public-subnet"
  }
}

resource "aws_internet_gateway" "minecraft" {
  vpc_id = aws_vpc.minecraft.id

  tags = {
    Name = "cs312-course-project-2-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.minecraft.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.minecraft.id
  }

  tags = {
    Name = "cs312-course-project-2-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "minecraft" {
  name        = "cs312-course-project-2-sg"
  description = "Permit automated administration and Minecraft connectivity"
  vpc_id      = aws_vpc.minecraft.id

  ingress {
    description = "Automated Ansible management from the control node"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Minecraft server connection and TCP nmap verification"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Minecraft query protocol"
    from_port   = 25565
    to_port     = 25565
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Permit outbound updates and image downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cs312-course-project-2-sg"
  }
}

resource "aws_key_pair" "minecraft" {
  key_name   = "cs312-course-project-2-ansible-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Name = "cs312-course-project-2-ansible-key"
  }
}

resource "aws_instance" "minecraft" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  availability_zone           = "us-east-1c"
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.minecraft.id]
  key_name                    = aws_key_pair.minecraft.key_name

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 12
  }

  tags = {
    Name = "cs312-course-project-2-minecraft-server"
  }
}

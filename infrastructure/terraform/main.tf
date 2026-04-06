terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to use S3 remote state (recommended for production)
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "project-sauron/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# ──────────────────────────────────────────────
# VPC & Networking
# ──────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ──────────────────────────────────────────────
# Security Group
# ──────────────────────────────────────────────

resource "aws_security_group" "sauron" {
  name        = "${var.project_name}-sg"
  description = "Security group for Project Sauron observability stack"
  vpc_id      = aws_vpc.main.id

  # SSH — restrict to your IP in production
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
    description = "SSH access"
  }

  # Grafana UI
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.grafana_allowed_cidrs
    description = "Grafana dashboard"
  }

  # HTTP — redirects to HTTPS via Nginx/Caddy reverse proxy
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP (redirect to HTTPS)"
  }

  # HTTPS — Grafana UI + push endpoints (e.g. alloy remote_write)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS (Grafana + push endpoints)"
  }

  # Prometheus — internal only (not exposed to public internet)
  # Access via SSH tunnel: ssh -L 9090:localhost:9090 ec2-user@<ip>
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (for Docker pulls, CloudWatch API, etc.)"
  }

  tags = { Name = "${var.project_name}-sg" }
}

# ──────────────────────────────────────────────
# IAM — CloudWatch Read Access
# ──────────────────────────────────────────────

resource "aws_iam_role" "sauron_ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "cloudwatch_read" {
  name = "${var.project_name}-cloudwatch-read"
  role = aws_iam_role.sauron_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "tag:GetResources"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "sauron_ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.sauron_ec2.name
}

# ──────────────────────────────────────────────
# EC2 Key Pair
# ──────────────────────────────────────────────

resource "aws_key_pair" "sauron" {
  key_name   = "${var.project_name}-key"
  public_key = var.ec2_public_key

  tags = { Name = "${var.project_name}-keypair" }
}

# ──────────────────────────────────────────────
# EC2 Instance
# ──────────────────────────────────────────────

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "sauron" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.sauron.id]
  key_name               = aws_key_pair.sauron.key_name
  iam_instance_profile   = aws_iam_instance_profile.sauron_ec2.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail

    # Install Docker
    dnf update -y
    dnf install -y docker git
    systemctl enable --now docker
    usermod -aG docker ec2-user

    # Install Docker Compose v2
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # Clone the repo
    git clone https://github.com/7ports/project-sauron.git /opt/project-sauron
    chown -R ec2-user:ec2-user /opt/project-sauron
    EOF
  )

  tags = { Name = "${var.project_name}-server" }
}

# ──────────────────────────────────────────────
# Route53 DNS
# ──────────────────────────────────────────────

resource "aws_route53_zone" "root" {
  name    = "7ports.ca"
  comment = "Managed by Terraform — project-sauron"

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# sauron.7ports.ca → EC2 Elastic IP
# Toggled off by default — enable only after updating registrar nameservers to Route53 NS records
resource "aws_route53_record" "sauron" {
  count   = var.enable_dns ? 1 : 0
  zone_id = aws_route53_zone.root.zone_id
  name    = "sauron.${aws_route53_zone.root.name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.sauron.public_ip]
}

# 7ports.ca apex → WordPress Lightsail static IP
# Preserves the existing WordPress site during DNS migration to Route53
resource "aws_route53_record" "wordpress_apex" {
  zone_id = aws_route53_zone.root.zone_id
  name    = aws_route53_zone.root.name
  type    = "A"
  ttl     = 300
  records = [var.wordpress_lightsail_ip]
}

# www.7ports.ca → WordPress Lightsail static IP
resource "aws_route53_record" "wordpress_www" {
  zone_id = aws_route53_zone.root.zone_id
  name    = "www.${aws_route53_zone.root.name}"
  type    = "A"
  ttl     = 300
  records = [var.wordpress_lightsail_ip]
}

# ──────────────────────────────────────────────
# Elastic IP
# ──────────────────────────────────────────────

resource "aws_eip" "sauron" {
  instance = aws_instance.sauron.id
  domain   = "vpc"

  tags = { Name = "${var.project_name}-eip" }
}

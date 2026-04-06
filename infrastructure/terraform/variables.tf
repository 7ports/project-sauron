variable "project_name" {
  description = "Project name used as a prefix for all resources"
  type        = string
  default     = "project-sauron"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for the observability server"
  type        = string
  default     = "t3.small"
}

variable "ec2_public_key" {
  description = "SSH public key to install on the EC2 instance (contents of your ~/.ssh/id_rsa.pub or similar)"
  type        = string
  sensitive   = true
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH into the instance. Restrict to your IP for security."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "grafana_allowed_cidrs" {
  description = "CIDR blocks allowed to access Grafana (port 3000)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

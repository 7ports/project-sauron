output "elastic_ip" {
  description = "Elastic IP address of the Sauron observability server"
  value       = aws_eip.sauron.public_ip
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.sauron.id
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${aws_eip.sauron.public_ip}:3000"
}

output "prometheus_tunnel_command" {
  description = "SSH tunnel command to access Prometheus locally"
  value       = "ssh -L 9090:localhost:9090 -i <your-key.pem> ec2-user@${aws_eip.sauron.public_ip}"
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i <your-key.pem> ec2-user@${aws_eip.sauron.public_ip}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

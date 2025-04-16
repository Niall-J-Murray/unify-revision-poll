output "app_url" {
  description = "The URL of the deployed application"
  value       = "https://${var.subdomain_name}.${var.domain_name}"
}

output "db_endpoint" {
  description = "The connection endpoint for the RDS database instance"
  value       = aws_db_instance.main.endpoint
}

output "secret_arns" {
  description = "The ARN of the Secrets Manager secret containing application environment variables"
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository for the application image"
  value       = aws_ecr_repository.app.repository_url
}

output "rds_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.main.endpoint
}

output "terraform_caller_arn" {
  description = "The ARN of the identity used by Terraform to authenticate."
  value       = data.aws_caller_identity.current.arn
}

output "bastion_host_instance_id" {
  description = "The instance ID of the EC2 Bastion Host used for SSH access."
  value       = aws_instance.bastion_host.id
}

output "bastion_public_ip" {
  description = "The public IP address of the EC2 Bastion Host."
  value       = aws_instance.bastion_host.public_ip
} 
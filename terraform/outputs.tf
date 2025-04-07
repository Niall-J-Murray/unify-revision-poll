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
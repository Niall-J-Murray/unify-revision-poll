variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-1"
}

variable "availability_zone_a" {
  description = "Primary availability zone (e.g., eu-west-1a)"
  type        = string
  default     = "eu-west-1a"
}

variable "availability_zone_b" {
  description = "Secondary availability zone (e.g., eu-west-1b)"
  type        = string
  default     = "eu-west-1b"
}

variable "domain_name" {
  description = "The domain name for the application"
  type        = string
  default     = "murrdev.com"
}

variable "subdomain_name" {
  description = "The subdomain for the application"
  type        = string
  default     = "feature-poll"
}

variable "ec2_instance_type" {
  description = "EC2 instance type for ECS"
  type        = string
  default     = "t3.small"
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_storage_type" {
  description = "RDS storage type"
  type        = string
  default     = "gp2"
}

variable "rds_db_name" {
  description = "Database name"
  type        = string
  default     = "featurepolldb"
}

variable "rds_db_user" {
  description = "Database username"
  type        = string
  default     = "dbadmin"
}

variable "rds_db_password" {
  description = "Database password (use a strong password in production, this is for testing)"
  type        = string
  default     = "pass1234" # Note: Hardcoding sensitive values is not recommended for production. Use variable inputs or secrets management.
  sensitive   = true
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the domain"
  type        = string
  # This needs to be provided manually or via data source after creation/validation
}

variable "container_port" {
  description = "The port the container listens on"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "The path for the health check endpoint"
  type        = string
  default     = "/api/health" # Updated based on Dockerfile
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 5
}

variable "tags" {
  description = "A map of tags to assign to resources"
  type        = map(string)
  default = {
    Project   = "FeaturePollApp"
    ManagedBy = "Terraform"
  }
} 
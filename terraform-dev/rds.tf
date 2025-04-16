# Create the new subnet group with public subnets
resource "aws_db_subnet_group" "rds" {
  name = "${var.subdomain_name}-rds-subnet-group"
  # Use both private subnets across the two AZs (Reflecting actual state)
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-rds-subnet-group"
  })
}

resource "aws_db_instance" "main" {
  identifier             = "${var.subdomain_name}-db"
  allocated_storage      = var.rds_allocated_storage
  storage_type           = var.rds_storage_type
  engine                 = "postgres"
  engine_version         = "17.2" # Match actual reported version
  instance_class         = var.rds_instance_class
  db_name                = var.rds_db_name
  username               = var.rds_db_user
  password               = var.rds_db_password
  parameter_group_name   = "default.postgres17"
  # Point back to the original (private) subnet group
  db_subnet_group_name   = aws_db_subnet_group.rds.name 
  vpc_security_group_ids = [aws_security_group.ecs_task.id]

  # Cost Optimization Settings
  multi_az                     = false # Disable Multi-AZ (Still allowed even with multi-AZ subnet group)
  publicly_accessible          = false  # Should not be publicly accessible for private setup
  performance_insights_enabled = false # Disable Performance Insights
  backup_retention_period      = 1     # 1-day backup retention
  skip_final_snapshot          = true  # Skip final snapshot on deletion
  apply_immediately            = true  # Apply changes immediately (can be false for production workflows)

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-db-instance"
  })
}

# Note: Security Group rules allowing access to RDS are defined in main.tf 
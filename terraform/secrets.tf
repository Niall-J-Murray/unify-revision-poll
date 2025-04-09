locals {
  # Attempt to read the .env file from the parent directory
  # Note: This assumes the .env file exists one level up from the terraform directory.
  # Adjust the path if your .env file is located elsewhere.
  raw_env_content = fileexists("../.env") ? file("../.env") : ""

  # 1. Split into lines and filter out invalid/empty/comment lines
  valid_lines = [
    for line in split("\n", local.raw_env_content) :
    trimspace(line)
    # Conditions: line is not empty, not a comment, and CAN match the '=' regex
    if length(trimspace(line)) > 0 && !startswith(trimspace(line), "#") && can(regex("=", line))
  ]

  # 2. Process only the valid lines using regex to build the map
  env_vars = sensitive({
    # Structure: for <item> in <collection> : <key> => <value>
    for line in local.valid_lines :
    # Key: Trimmed first capture group from regex
    trimspace(regex("^([^=]+)=(.*)$", line)[0]) =>
    # Value: Trimmed second capture group from regex
    trimspace(regex("^([^=]+)=(.*)$", line)[1])
  })

  # Include database credentials and other necessary variables
  app_secrets = merge(local.env_vars, {
    NODE_ENV     = "production"
    DATABASE_URL = "postgresql://${var.rds_db_user}:${var.rds_db_password}@${aws_db_instance.main.address}/${var.rds_db_name}"
    # DIRECT_URL is often the same as DATABASE_URL for non-pooled connections
    DIRECT_URL   = "postgresql://${var.rds_db_user}:${var.rds_db_password}@${aws_db_instance.main.address}/${var.rds_db_name}"
    NEXTAUTH_URL = "https://${var.subdomain_name}.${var.domain_name}"
    # Add any other required runtime environment variables here
    # If the .env file contains keys matching these (e.g., NEXTAUTH_URL), 
    # the values defined here will take precedence due to the merge order.
  })
}

resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "/${var.subdomain_name}/${var.domain_name}/app-secrets"
  description = "Application environment variables for ${var.subdomain_name}.${var.domain_name}"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "app_secrets_version" {
  secret_id     = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode(local.app_secrets)

  lifecycle {
    ignore_changes = [
      secret_string, # Ignore changes to prevent recreation on every apply if .env changes
    ]
  }
} 
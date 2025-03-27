# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Starting deployment process..."

# Source variables
Write-Host "Step 0: Setting up variables..."
. "$ScriptDir\01-setup-variables.ps1"

# Configure AWS CLI
Write-Host "Step 1: Configuring AWS CLI..."
. "$ScriptDir\02-configure-aws-cli.ps1"

# Create VPC
Write-Host "Step 2: Creating VPC..."
. "$ScriptDir\03-create-vpc.ps1"

# Create RDS
Write-Host "Step 3: Creating RDS database..."
. "$ScriptDir\04-create-rds.ps1"

# Create ECR repository
Write-Host "Step 4: Creating ECR repository..."
. "$ScriptDir\05-create-ecr.ps1"

# Push Docker image
Write-Host "Step 5: Building and pushing Docker image..."
. "$ScriptDir\06-push-docker.ps1"

# Create SSL certificate
Write-Host "Step 6: Creating SSL certificate..."
. "$ScriptDir\07-create-ssl-certificate.ps1"

# Create Secrets
Write-Host "Step 7: Creating Secrets Manager secret..."
. "$ScriptDir\06-create-secrets.ps1" # Note: Naming is slightly out of order

# Create ECS Resources (Cluster, Task Def, Service, ALB, SGs, Listeners)
Write-Host "Step 8: Creating ECS resources (Service, ALB, etc)..."
. "$ScriptDir\07-create-ecs-resources.ps1" # Note: Naming is slightly out of order

# Create Route 53 Record
Write-Host "Step 9: Creating Route 53 record..."
. "$ScriptDir\08-create-route53-record.ps1"

# Finalize Deployment (Wait for service stability)
Write-Host "Step 10: Finalizing deployment..."
. "$ScriptDir\09-finalize-deployment.ps1"

Write-Host "Deployment process initiated. Final status will be shown by the finalize script."
# Write-Host "Your application will be available at https://${SUBDOMAIN}.${DOMAIN_NAME}" # Moved to finalize script 
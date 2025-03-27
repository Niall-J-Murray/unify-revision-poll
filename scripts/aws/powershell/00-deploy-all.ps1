# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Starting deployment process..."

# Source variables
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

Write-Host "Deployment completed successfully!"
Write-Host "Your application will be available at https://${SUBDOMAIN}.${DOMAIN_NAME}" 
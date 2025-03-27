#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Starting deployment process..."

# Source variables
echo "Step 0: Setting up variables..."
source "$SCRIPT_DIR/01-setup-variables.sh"

# Configure AWS CLI
echo "Step 1: Configuring AWS CLI..."
source "$SCRIPT_DIR/02-configure-aws-cli.sh"

# Create VPC
echo "Step 2: Creating VPC..."
source "$SCRIPT_DIR/03-create-vpc.sh"

# Create RDS
echo "Step 3: Creating RDS database..."
source "$SCRIPT_DIR/04-create-rds.sh"

# Create ECR repository
echo "Step 4: Creating ECR repository..."
source "$SCRIPT_DIR/05-create-ecr.sh"

# Push Docker image
echo "Step 5: Building and pushing Docker image..."
source "$SCRIPT_DIR/06-push-docker.sh"

# Create SSL certificate
echo "Step 6: Creating SSL certificate..."
source "$SCRIPT_DIR/07-create-ssl-certificate.sh"

# Create Secrets
echo "Step 7: Creating Secrets Manager secret..."
source "$SCRIPT_DIR/06-create-secrets.sh" # Note: Naming is slightly out of order

# Create ECS Resources (Cluster, Task Def, Service, ALB, SGs, Listeners)
echo "Step 8: Creating ECS resources (Service, ALB, etc)..."
source "$SCRIPT_DIR/07-create-ecs-resources.sh" # Note: Naming is slightly out of order

# Create Route 53 Record
echo "Step 9: Creating Route 53 record..."
source "$SCRIPT_DIR/08-create-route53-record.sh"

# Finalize Deployment (Wait for service stability)
echo "Step 10: Finalizing deployment..."
source "$SCRIPT_DIR/09-finalize-deployment.sh"

echo "Deployment process initiated. Final status will be shown by the finalize script."
# echo "Your application will be available at https://${SUBDOMAIN}.${DOMAIN_NAME}" # Moved to finalize script 
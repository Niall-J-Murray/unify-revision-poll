#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Main deployment script for the unify-revision-poll application

echo "Starting full AWS deployment for unify-revision-poll..."
echo "This process will deploy the entire infrastructure and may take 30-60 minutes."

# Make all scripts executable
chmod +x "$SCRIPT_DIR"/*.sh

# Step 0: Configure AWS CLI
echo "Step 0/10: Configuring AWS CLI"
"$SCRIPT_DIR/00-configure-aws-cli.sh"

# Step 1: Set up environment variables
echo "Step 1/10: Setting up environment variables"
"$SCRIPT_DIR/01-setup-variables.sh"

# Step 2: Create VPC, subnets, and Internet Gateway
echo "Step 2/10: Creating VPC, subnets, and Internet Gateway"
"$SCRIPT_DIR/02-create-vpc.sh"

# Step 3: Create RDS PostgreSQL database
echo "Step 3/10: Creating RDS PostgreSQL database"
"$SCRIPT_DIR/03-create-rds.sh"

# Step 4: Create ECR repository and push Docker image
echo "Step 4/10: Creating ECR repository and pushing Docker image"
"$SCRIPT_DIR/04-create-ecr-push-image.sh"

# Step 5: Create SSL certificate and initial Route 53 records
echo "Step 5/10: Creating SSL certificate and initial Route 53 records"
"$SCRIPT_DIR/05-create-ssl-certificate.sh"

# Step 6: Create secrets for environment variables
echo "Step 6/10: Creating secrets for environment variables"
"$SCRIPT_DIR/06-create-secrets.sh"

# Step 7: Create ECS resources (cluster, task definition, service)
echo "Step 7/10: Creating ECS resources"
"$SCRIPT_DIR/07-create-ecs-resources.sh"

# Step 8: Create Route 53 record for the domain
echo "Step 8/10: Creating Route 53 records"
"$SCRIPT_DIR/08-create-route53-record.sh"

# Step 9: Finalize deployment and show summary
echo "Step 9/10: Finalizing deployment"
"$SCRIPT_DIR/09-finalize-deployment.sh"

echo "Full deployment process completed!"
echo "Your application should be accessible at https://${SUBDOMAIN}.${DOMAIN_NAME} shortly."
echo "Note that DNS propagation and certificate validation may take some time." 
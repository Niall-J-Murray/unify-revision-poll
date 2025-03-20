#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Create .aws directory in scripts/aws if it doesn't exist
mkdir -p "$SCRIPT_DIR/.aws"

echo "Setting up environment variables for AWS deployment..."

# AWS Region
export AWS_REGION="eu-west-1"

# Application name
export APP_NAME="unify-revision-poll"

# VPC and network settings
export VPC_CIDR="10.0.0.0/16"
export PUBLIC_SUBNET_1_CIDR="10.0.1.0/24"
export PUBLIC_SUBNET_2_CIDR="10.0.2.0/24"
export PRIVATE_SUBNET_1_CIDR="10.0.3.0/24"
export PRIVATE_SUBNET_2_CIDR="10.0.4.0/24"

# Domain settings
export DOMAIN_NAME="niallmurray.me"
export SUBDOMAIN="revision-poll"

# Database settings
export DB_NAME="revisionpoll"
export DB_USERNAME="revisionpoll_admin"
export DB_PASSWORD=$(openssl rand -base64 16)
export DB_PORT="5432"
export DB_INSTANCE_CLASS="db.t3.micro"
export DB_ALLOCATED_STORAGE="20"

# ECS settings
export ECS_TASK_CPU="256"
export ECS_TASK_MEMORY="512"
export ECS_CONTAINER_PORT="3000"
export ECS_SERVICE_COUNT="1"

# ECR repository name
export ECR_REPO_NAME="${APP_NAME}"

echo "Environment variables are set:"
echo "AWS Region: $AWS_REGION"
echo "Application name: $APP_NAME"
echo "VPC CIDR: $VPC_CIDR"
echo "Domain: ${SUBDOMAIN}.${DOMAIN_NAME}"
echo "Database name: $DB_NAME"
echo "Database password is generated and will be saved securely."

# Save the variables to a file for non-bash scripts to source
cat > "$SCRIPT_DIR/.aws/env.sh" << EOF
#!/bin/bash

# AWS Region
export AWS_REGION="$AWS_REGION"

# Application name
export APP_NAME="$APP_NAME"

# VPC and network settings
export VPC_CIDR="$VPC_CIDR"
export PUBLIC_SUBNET_1_CIDR="$PUBLIC_SUBNET_1_CIDR"
export PUBLIC_SUBNET_2_CIDR="$PUBLIC_SUBNET_2_CIDR"
export PRIVATE_SUBNET_1_CIDR="$PRIVATE_SUBNET_1_CIDR"
export PRIVATE_SUBNET_2_CIDR="$PRIVATE_SUBNET_2_CIDR"

# Domain settings
export DOMAIN_NAME="$DOMAIN_NAME"
export SUBDOMAIN="$SUBDOMAIN"

# Database settings
export DB_NAME="$DB_NAME"
export DB_USERNAME="$DB_USERNAME"
export DB_PASSWORD="$DB_PASSWORD"
export DB_PORT="$DB_PORT"
export DB_INSTANCE_CLASS="$DB_INSTANCE_CLASS"
export DB_ALLOCATED_STORAGE="$DB_ALLOCATED_STORAGE"

# ECS settings
export ECS_TASK_CPU="$ECS_TASK_CPU"
export ECS_TASK_MEMORY="$ECS_TASK_MEMORY"
export ECS_CONTAINER_PORT="$ECS_CONTAINER_PORT"
export ECS_SERVICE_COUNT="$ECS_SERVICE_COUNT"

# ECR repository name
export ECR_REPO_NAME="${ECR_REPO_NAME}"
EOF

chmod +x "$SCRIPT_DIR/.aws/env.sh"

echo "Setup completed and variables saved to $SCRIPT_DIR/.aws/env.sh" 
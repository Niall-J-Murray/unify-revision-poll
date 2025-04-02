#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Starting full AWS deployment for $APP_NAME..."

# --- Step 0: Setup Variables & Config ---
echo "Step 0: Setting up variables & configuring AWS CLI..."
source "$SCRIPT_DIR/01-setup-variables.sh" || { echo "Failed Step 0: Variable setup"; exit 1; }
source "$SCRIPT_DIR/02-configure-aws-cli.sh" || { echo "Failed Step 0: AWS CLI configuration"; exit 1; }

# --- Step 0b: Hosted Zone Setup ---
echo "Step 0b: Checking/Creating Route 53 Hosted Zone..."
source "$SCRIPT_DIR/02b-create-hosted-zone.sh" || { echo "Failed Step 0b: Hosted Zone setup"; exit 1; }
# Manual Step Reminder: Update registrar nameservers after this if zone was created!

# --- Step 1: Networking --- 
echo "Step 1: Setting up Networking (VPC, Subnets, NAT GW, Endpoints)..."
source "$SCRIPT_DIR/03-setup-networking.sh" || { echo "Failed Step 1: Networking setup"; exit 1; }

# --- Step 2: Database --- 
echo "Step 2: Creating RDS database..."
source "$SCRIPT_DIR/04-create-rds.sh" || { echo "Failed Step 2: RDS creation"; exit 1; }

# --- Step 3: Bastion Host (Optional but recommended) --- 
echo "Step 3: Setting up Bastion Host..."
source "$SCRIPT_DIR/04b-setup-bastion.sh" || { echo "Failed Step 3: Bastion setup"; exit 1; }

# --- Step 4: Container Registry --- 
echo "Step 4: Creating ECR repository..."
source "$SCRIPT_DIR/05-create-ecr.sh" || { echo "Failed Step 4: ECR creation"; exit 1; }

# --- Step 5: Build & Push Image --- 
echo "Step 5: Building and pushing Docker image..."
source "$SCRIPT_DIR/06-build-push-docker.sh" || { echo "Failed Step 5: Docker build/push"; exit 1; }

# --- Step 6: Secrets --- 
echo "Step 6: Creating/Updating SSM Parameters..."
source "$SCRIPT_DIR/07-create-secrets.sh" || { echo "Failed Step 6: Secrets creation"; exit 1; }

# --- Step 7: Domain/SSL/DNS --- 
echo "Step 7: Setting up Domain, SSL, and DNS..."
source "$SCRIPT_DIR/08-setup-domain-ssl.sh" || { echo "Failed Step 7: Domain/SSL/DNS setup"; exit 1; }

# --- Step 8: ECS Resources (Cluster, ALB, Task Def, Service, IAM Permissions) --- 
echo "Step 8: Creating ECS resources (Cluster, ALB, Service, Permissions)..."
source "$SCRIPT_DIR/09-create-ecs-resources.sh" || { echo "Failed Step 8: ECS resource creation"; exit 1; }

# --- Step 8b: Create Final DNS Record (after ALB exists) ---
echo "Step 8b: Creating final DNS record..."
source "$SCRIPT_DIR/09b-create-dns-record.sh" || { echo "Failed Step 8b: DNS record creation"; exit 1; }

# --- Step 9: Finalize & Wait --- 
echo "Step 9: Finalizing deployment and waiting for service..."
source "$SCRIPT_DIR/10-finalize-deployment.sh" || { echo "Failed Step 9: Deployment finalization"; exit 1; }

# Step 10 would be manual verification or running the diagnose script

echo "--------------------------------------------"
echo "Full Deployment Script Finished."
echo "Check the output of Step 9 for the application URL and status."
echo "If issues occur, run: sh scripts/aws/bash/11-diagnose-ecs.sh"
echo "--------------------------------------------" 
#!/bin/bash

# Script to scale up AWS resources via Terraform and start the RDS instance

# --- Configuration ---
RDS_INSTANCE_IDENTIFIER="feature-poll-db" # Change this if your identifier is different
TERRAFORM_DIR="." # Assumes running from the terraform-dev directory
AWS_REGION="eu-west-1" # Change this if your region is different

# --- Check AWS CLI Login Status ---
echo "Checking AWS CLI status..."
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "AWS CLI is not configured or logged in. Please configure AWS CLI and try again."
  exit 1
else
  echo "AWS CLI is configured."
fi

# --- Run Terraform Apply ---
echo "Running terraform apply to enable resources (set is_enabled=true)..."
cd "${TERRAFORM_DIR}"

# Initialize Terraform if needed (optional, uncomment if first run or modules changed)
# echo "Running terraform init..."
# terraform init -upgrade

echo "Running terraform apply..."
# Use the default value (true) for is_enabled or explicitly set it
terraform apply -var="is_enabled=true" -auto-approve

if [ $? -ne 0 ]; then
  echo "Terraform apply failed. Please check the output above."
  exit 1
fi

echo "Terraform apply completed. Infrastructure (EC2 instance, ECS service) is being created/scaled up."
echo "This may take several minutes."

# --- Start RDS Instance ---
echo "Attempting to start RDS instance: ${RDS_INSTANCE_IDENTIFIER}..."
aws rds start-db-instance \
  --db-instance-identifier "${RDS_INSTANCE_IDENTIFIER}" \
  --region "${AWS_REGION}"

START_STATUS=$?
if [ ${START_STATUS} -ne 0 ]; then
  # Check if the error is because it's already available
  aws rds describe-db-instances --db-instance-identifier "${RDS_INSTANCE_IDENTIFIER}" --region "${AWS_REGION}" --query "DBInstances[?DBInstanceStatus=='available']" --output text | grep -q "${RDS_INSTANCE_IDENTIFIER}"
  if [ $? -eq 0 ]; then
    echo "RDS instance ${RDS_INSTANCE_IDENTIFIER} is already started and available."
  else
    echo "Error starting RDS instance. AWS CLI exit code: ${START_STATUS}. Please check AWS console or logs."
    # Decide if you want to exit or continue
    # exit 1
  fi
else
  echo "Start command issued for RDS instance ${RDS_INSTANCE_IDENTIFIER}. It may take several minutes to become available."
fi

echo "--- Start script finished ---"
echo "Wait for the EC2 instance, ECS service, and RDS instance to become fully available before accessing the application." 
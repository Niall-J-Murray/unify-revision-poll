#!/bin/bash

# Script to stop the RDS instance and scale down AWS resources via Terraform

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

# --- Stop RDS Instance ---
echo "Attempting to stop RDS instance: ${RDS_INSTANCE_IDENTIFIER}..."
aws rds stop-db-instance \
  --db-instance-identifier "${RDS_INSTANCE_IDENTIFIER}" \
  --region "${AWS_REGION}" 

STOP_STATUS=$?
if [ ${STOP_STATUS} -ne 0 ]; then
  # Check if the error is because it's already stopped
  aws rds describe-db-instances --db-instance-identifier "${RDS_INSTANCE_IDENTIFIER}" --region "${AWS_REGION}" --query "DBInstances[?DBInstanceStatus=='stopped']" --output text | grep -q "${RDS_INSTANCE_IDENTIFIER}"
  if [ $? -eq 0 ]; then
    echo "RDS instance ${RDS_INSTANCE_IDENTIFIER} is already stopped."
  else
    echo "Error stopping RDS instance. AWS CLI exit code: ${STOP_STATUS}. Please check AWS console or logs."
    # Decide if you want to exit or continue with terraform
    # exit 1 
  fi
else
  echo "Stop command issued for RDS instance ${RDS_INSTANCE_IDENTIFIER}. It may take a few minutes to fully stop."
fi

# --- Run Terraform Apply ---
echo "Running terraform apply to disable resources (set is_enabled=false)..."
cd "${TERRAFORM_DIR}"

# Initialize Terraform if needed (optional, uncomment if first run or modules changed)
# echo "Running terraform init..."
# terraform init -upgrade

echo "Running terraform apply..."
terraform apply -var="is_enabled=false" -auto-approve

if [ $? -ne 0 ]; then
  echo "Terraform apply failed. Please check the output above."
  exit 1
fi

echo "--- Stop script finished ---"
echo "Resources are being scaled down."
echo "Remember: RDS storage costs still apply while the instance is stopped." 
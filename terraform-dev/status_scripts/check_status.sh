#!/bin/bash

# Script to check the status of AWS resources after running stop_app.sh

# --- Configuration ---
RDS_INSTANCE_IDENTIFIER="feature-poll-db"
ECS_CLUSTER_NAME="feature-poll-cluster"
ECS_SERVICE_NAME_PREFIX="feature-poll-app-service" # Prefix or full name if static
ASG_NAME_PREFIX="feature-poll-ecs-asg"      # Prefix used to find the ASG
EC2_INSTANCE_TAG_NAME="feature-poll-ecs-instance"
AWS_REGION="eu-west-1"

# --- Check AWS CLI Login Status ---
echo "Checking AWS CLI status..."
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "AWS CLI is not configured or logged in. Please configure AWS CLI and try again."
  exit 1
else
  echo "AWS CLI is configured."
  echo "------------------------------------"
fi

# 1. Check RDS Instance Status
echo "1. Checking RDS Instance Status (${RDS_INSTANCE_IDENTIFIER})..."
RDS_STATUS=$(aws rds describe-db-instances --db-instance-identifier "${RDS_INSTANCE_IDENTIFIER}" --query "DBInstances[*].DBInstanceStatus" --output text --region "${AWS_REGION}" 2>/dev/null)
if [ -z "${RDS_STATUS}" ]; then
  echo "   ERROR: Could not retrieve status for RDS instance ${RDS_INSTANCE_IDENTIFIER}. It might not exist or there was an API error."
elif [ "${RDS_STATUS}" == "stopped" ]; then
  echo "   OK: RDS instance status is '${RDS_STATUS}'."
else
  echo "   WARN: Expected RDS status 'stopped', but got '${RDS_STATUS}'."
fi
echo "------------------------------------"

# 2. Check ECS Service Status
echo "2. Checking ECS Service Status in cluster (${ECS_CLUSTER_NAME})..."
# List services that potentially match the name prefix (Terraform adds [0] when count > 0)
SERVICE_ARNS=$(aws ecs list-services --cluster "${ECS_CLUSTER_NAME}" --query "serviceArns[?contains(@, '${ECS_SERVICE_NAME_PREFIX}')]" --output text --region "${AWS_REGION}")

if [ -z "${SERVICE_ARNS}" ]; then
  echo "   OK: No ECS service matching '${ECS_SERVICE_NAME_PREFIX}' found in cluster '${ECS_CLUSTER_NAME}'. (Expected when disabled)"
else
  echo "   WARN: Found potentially matching ECS service(s): ${SERVICE_ARNS}"
  # Optionally describe the found services
  # aws ecs describe-services --cluster "${ECS_CLUSTER_NAME}" --services ${SERVICE_ARNS} --query "services[*].[serviceName, desiredCount, runningCount]" --output table --region "${AWS_REGION}"
fi
echo "------------------------------------"

# 3. Check Auto Scaling Group Capacity
echo "3. Checking Auto Scaling Group Capacity (Prefix: ${ASG_NAME_PREFIX})..."
ASG_NAME=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?contains(AutoScalingGroupName, '${ASG_NAME_PREFIX}')].AutoScalingGroupName" --output text --region "${AWS_REGION}" | head -n 1) # Get the first match if multiple exist

if [ -z "${ASG_NAME}" ]; then
  echo "   ERROR: Could not find an ASG with prefix '${ASG_NAME_PREFIX}'."
else
  echo "   Found ASG: ${ASG_NAME}"
  ASG_COUNTS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG_NAME}" --query "AutoScalingGroups[*].[MinSize, MaxSize, DesiredCapacity]" --output text --region "${AWS_REGION}")
  EXPECTED_COUNTS="0	0	0"
  if [ "${ASG_COUNTS}" == "${EXPECTED_COUNTS}" ]; then
    echo "   OK: ASG counts (Min/Max/Desired) are '${ASG_COUNTS}'."
  else
    echo "   WARN: Expected ASG counts '${EXPECTED_COUNTS}', but got '${ASG_COUNTS}'."
  fi
fi
echo "------------------------------------"

# 4. Check Running EC2 Instances
echo "4. Checking for running EC2 instances tagged Name=${EC2_INSTANCE_TAG_NAME}..."
RUNNING_INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${EC2_INSTANCE_TAG_NAME}" "Name=instance-state-name,Values=running,pending" --query "Reservations[*].Instances[*].InstanceId" --output text --region "${AWS_REGION}")

if [ -z "${RUNNING_INSTANCES}" ]; then
  echo "   OK: No running or pending instances found with tag Name=${EC2_INSTANCE_TAG_NAME}."
else
  echo "   WARN: Found running or pending instances: ${RUNNING_INSTANCES}"
fi
echo "------------------------------------"

echo "Check script finished." 
#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source all the configuration files
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$SCRIPT_DIR/vpc-config.sh"
source "$SCRIPT_DIR/rds-config.sh"
source "$SCRIPT_DIR/ecr-config.sh"
source "$SCRIPT_DIR/certificate-config.sh"
source "$SCRIPT_DIR/secrets-config.sh"
source "$SCRIPT_DIR/alb-config.sh"

echo "Finalizing deployment..."

# Wait for the ECS service to be stable
echo "Waiting for ECS service to be stable..."
aws ecs wait services-stable \
  --cluster ${APP_NAME}-cluster \
  --services ${APP_NAME}-service \
  --region $AWS_REGION

echo "ECS service is stable"

# Get the task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster ${APP_NAME}-cluster \
  --service-name ${APP_NAME}-service \
  --query 'taskArns[0]' \
  --output text \
  --region $AWS_REGION)

if [ -z "$TASK_ARN" ]; then
  echo "No tasks found in the service"
  exit 1
fi

echo "Found task ARN: $TASK_ARN"

# Get the task IP address
TASK_IP=$(aws ecs describe-tasks \
  --cluster ${APP_NAME}-cluster \
  --tasks $TASK_ARN \
  --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value[0]' \
  --output text \
  --region $AWS_REGION)

if [ -z "$TASK_IP" ]; then
  echo "No IP address found for the task"
  exit 1
fi

echo "Found task IP: $TASK_IP"

# Register the task IP with the target group
aws elbv2 register-targets \
  --target-group-arn $TARGET_GROUP_ARN \
  --targets Id=$TASK_IP,Port=$ECS_CONTAINER_PORT \
  --region $AWS_REGION

echo "Registered task with target group"

# Wait for the target to be healthy
echo "Waiting for target to be healthy..."
aws elbv2 wait target-in-service \
  --target-group-arn $TARGET_GROUP_ARN \
  --targets Id=$TASK_IP,Port=$ECS_CONTAINER_PORT \
  --region $AWS_REGION

echo "Target is healthy"

# Get the application URL
APP_URL="https://${SUBDOMAIN}.${DOMAIN_NAME}"

echo "Deployment completed successfully!"
echo "Your application is available at: $APP_URL"
echo "Please wait a few minutes for DNS propagation to complete."
echo "You can check the application status by visiting: $APP_URL/api/health" 
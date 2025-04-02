#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"

# Source all the configuration files
source "$SCRIPT_DIR/01-setup-variables.sh"
[ -f "$CONFIG_DIR/vpc-config.sh" ] && source "$CONFIG_DIR/vpc-config.sh"
[ -f "$CONFIG_DIR/rds-config.sh" ] && source "$CONFIG_DIR/rds-config.sh"
[ -f "$CONFIG_DIR/ecr-config.sh" ] && source "$CONFIG_DIR/ecr-config.sh"
[ -f "$CONFIG_DIR/certificate-config.sh" ] && source "$CONFIG_DIR/certificate-config.sh"
[ -f "$CONFIG_DIR/secrets-config.sh" ] && source "$CONFIG_DIR/secrets-config.sh"
[ -f "$CONFIG_DIR/alb-config.sh" ] && source "$CONFIG_DIR/alb-config.sh"

echo "Finalizing deployment and waiting for service stability..."

# Check if Cluster and Service exist before waiting
if [ -z "$ECS_CLUSTER_NAME" ] || [ -z "$ECS_SERVICE_NAME" ]; then
    echo "Error: ECS_CLUSTER_NAME or ECS_SERVICE_NAME not set. Cannot check service status."
    exit 1
fi
CLUSTER_EXISTS=$(aws ecs describe-clusters --clusters ${ECS_CLUSTER_NAME} --query 'clusters[?status==`ACTIVE`].clusterArn' --output text --region $AWS_REGION 2>/dev/null)
SERVICE_EXISTS=$(aws ecs describe-services --cluster ${ECS_CLUSTER_NAME} --services ${ECS_SERVICE_NAME} --query 'services[?status==`ACTIVE`].serviceArn' --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$CLUSTER_EXISTS" ]; then echo "Error: ECS Cluster ${ECS_CLUSTER_NAME} not found or not active."; exit 1; fi
if [ -z "$SERVICE_EXISTS" ]; then echo "Error: ECS Service ${ECS_SERVICE_NAME} not found or not active in cluster ${ECS_CLUSTER_NAME}. Check 09-create-ecs-resources.sh logs."; exit 1; fi

echo "Waiting for ECS service ${ECS_SERVICE_NAME} to become stable... (This may take several minutes)"
WAIT_CMD="aws ecs wait services-stable --cluster ${ECS_CLUSTER_NAME} --services ${ECS_SERVICE_NAME} --region $AWS_REGION"
echo "Running: $WAIT_CMD"

$WAIT_CMD

if [ $? -ne 0 ]; then
    echo "Warning: Timed out waiting for service to become stable."
    echo "The service might still be deploying or encountering issues."
    echo "Checking current task status..."
    STOPPED_TASK_REASON=$(aws ecs list-tasks --cluster ${ECS_CLUSTER_NAME} --service-name ${ECS_SERVICE_NAME} --desired-status STOPPED --max-items 1 --query 'taskArns[0]' --output text --region $AWS_REGION 2>/dev/null | xargs -I {} aws ecs describe-tasks --cluster ${ECS_CLUSTER_NAME} --tasks {} --query 'tasks[0].stoppedReason' --output text --region $AWS_REGION 2>/dev/null)
    if [ -n "$STOPPED_TASK_REASON" ]; then echo "Reason for last stopped task: $STOPPED_TASK_REASON"; else echo "Could not determine reason for last stopped task (or no tasks have stopped recently). Check Service Events."; fi
    echo "Please check the ECS service events and CloudWatch logs for more details."
    echo "Consider running the diagnostic script: sh scripts/aws/bash/11-diagnose-ecs.sh"
fi

echo "ECS service stability check complete."

# Get the application URL
if [ -z "$SUBDOMAIN" ] || [ -z "$DOMAIN_NAME" ]; then
    echo "Warning: SUBDOMAIN or DOMAIN_NAME not set. Cannot construct application URL."
    APP_URL="<Check ALB DNS Name>"
else
    APP_URL="https://${SUBDOMAIN}.${DOMAIN_NAME}"
fi

echo ""
echo "Deployment process finished."
echo "Your application should be available at: $APP_URL"
echo "Note: It might take a few minutes for the service to fully stabilize and DNS to propagate."
echo "You can check the application status by visiting: $APP_URL/api/health"

exit 0
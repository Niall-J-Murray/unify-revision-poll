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

echo "Creating ECS resources..."

# Create ECS cluster
aws ecs create-cluster \
  --cluster-name ${APP_NAME}-cluster \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy capacityProvider=FARGATE_SPOT,weight=1 \
  --region $AWS_REGION

echo "Created ECS cluster: ${APP_NAME}-cluster"

# Create application load balancer security group
ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name ${APP_NAME}-alb-sg \
  --description "Security group for ${APP_NAME} ALB" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text \
  --region $AWS_REGION)

echo "Created ALB security group: $ALB_SG_ID"

# Allow HTTP and HTTPS traffic from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --region $AWS_REGION

aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  --region $AWS_REGION

echo "Configured ALB security group ingress rules"

# Create ECS task security group
ECS_SG_ID=$(aws ec2 create-security-group \
  --group-name ${APP_NAME}-ecs-sg \
  --description "Security group for ${APP_NAME} ECS tasks" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text \
  --region $AWS_REGION)

echo "Created ECS task security group: $ECS_SG_ID"

# Allow traffic from the ALB security group
aws ec2 authorize-security-group-ingress \
  --group-id $ECS_SG_ID \
  --protocol tcp \
  --port $ECS_CONTAINER_PORT \
  --source-group $ALB_SG_ID \
  --region $AWS_REGION

echo "Configured ECS task security group ingress rules"

# Create application load balancer
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name ${APP_NAME}-alb \
  --subnets $PUBLIC_SUBNET_1_ID $PUBLIC_SUBNET_2_ID \
  --security-groups $ALB_SG_ID \
  --scheme internet-facing \
  --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text \
  --region $AWS_REGION)

echo "Created application load balancer: $ALB_ARN"

# Create target group
TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
  --name ${APP_NAME}-tg \
  --protocol HTTP \
  --port $ECS_CONTAINER_PORT \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-path /api/health \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text \
  --region $AWS_REGION)

echo "Created target group: $TARGET_GROUP_ARN"

# Create HTTPS listener (once certificate is validated)
echo "Checking certificate validation status..."
aws acm wait certificate-validated \
  --certificate-arn $CERTIFICATE_ARN \
  --region $AWS_REGION || echo "Certificate validation still in progress. You'll need to create the HTTPS listener manually once it's validated."

# Try to create HTTPS listener
HTTPS_LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=$CERTIFICATE_ARN \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
  --query 'Listeners[0].ListenerArn' \
  --output text \
  --region $AWS_REGION) || echo "HTTPS listener creation failed. Will create HTTP listener only for now."

if [ -n "$HTTPS_LISTENER_ARN" ]; then
  echo "Created HTTPS listener: $HTTPS_LISTENER_ARN"
else
  echo "HTTPS listener creation skipped, certificate may still be validating."
fi

# Create HTTP listener (redirect to HTTPS if HTTPS listener exists, otherwise forward to target group)
if [ -n "$HTTPS_LISTENER_ARN" ]; then
  # Redirect to HTTPS
  HTTP_LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=redirect,RedirectConfig="{Protocol=HTTPS,Port=443,Host='#{host}',Path='#{path}',Query='#{query}',StatusCode=HTTP_301}" \
    --query 'Listeners[0].ListenerArn' \
    --output text \
    --region $AWS_REGION)
  
  echo "Created HTTP listener (redirect to HTTPS): $HTTP_LISTENER_ARN"
else
  # Forward to target group for now
  HTTP_LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn $ALB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
    --query 'Listeners[0].ListenerArn' \
    --output text \
    --region $AWS_REGION)
  
  echo "Created HTTP listener (forward to target): $HTTP_LISTENER_ARN"
fi

# Create IAM execution role for ECS tasks
ECS_EXECUTION_ROLE_NAME="${APP_NAME}-ecs-execution-role"

# Create IAM policy document for assume role
cat > "$SCRIPT_DIR/assume-role-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create IAM execution role
aws iam create-role \
  --role-name $ECS_EXECUTION_ROLE_NAME \
  --assume-role-policy-document file://"$SCRIPT_DIR/assume-role-policy.json" \
  --region $AWS_REGION

echo "Created IAM execution role: $ECS_EXECUTION_ROLE_NAME"

# Attach policies to the role
aws iam attach-role-policy \
  --role-name $ECS_EXECUTION_ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
  --region $AWS_REGION

# Create policy for Secrets Manager access
cat > "$SCRIPT_DIR/secrets-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "$SECRET_ARN"
      ]
    }
  ]
}
EOF

# Create and attach the secrets policy
SECRETS_POLICY_ARN=$(aws iam create-policy \
  --policy-name ${APP_NAME}-secrets-policy \
  --policy-document file://"$SCRIPT_DIR/secrets-policy.json" \
  --query 'Policy.Arn' \
  --output text \
  --region $AWS_REGION)

aws iam attach-role-policy \
  --role-name $ECS_EXECUTION_ROLE_NAME \
  --policy-arn $SECRETS_POLICY_ARN \
  --region $AWS_REGION

echo "Attached policies to IAM role"

# Get the execution role ARN
ECS_EXECUTION_ROLE_ARN=$(aws iam get-role \
  --role-name $ECS_EXECUTION_ROLE_NAME \
  --query 'Role.Arn' \
  --output text \
  --region $AWS_REGION)

echo "ECS execution role ARN: $ECS_EXECUTION_ROLE_ARN"

# Create task definition
cat > "$SCRIPT_DIR/task-definition.json" << EOF
{
  "family": "${APP_NAME}",
  "networkMode": "awsvpc",
  "executionRoleArn": "${ECS_EXECUTION_ROLE_ARN}",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "${ECS_TASK_CPU}",
  "memory": "${ECS_TASK_MEMORY}",
  "containerDefinitions": [
    {
      "name": "${APP_NAME}",
      "image": "${ECR_REPO_URI}:latest",
      "essential": true,
      "portMappings": [
        {
          "containerPort": ${ECS_CONTAINER_PORT},
          "hostPort": ${ECS_CONTAINER_PORT},
          "protocol": "tcp"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${APP_NAME}",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      },
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "${SECRET_ARN}:DATABASE_URL::"
        },
        {
          "name": "DIRECT_URL",
          "valueFrom": "${SECRET_ARN}:DIRECT_URL::"
        },
        {
          "name": "NEXT_PUBLIC_APP_URL",
          "valueFrom": "${SECRET_ARN}:NEXT_PUBLIC_APP_URL::"
        },
        {
          "name": "NEXTAUTH_URL",
          "valueFrom": "${SECRET_ARN}:NEXTAUTH_URL::"
        },
        {
          "name": "NEXTAUTH_SECRET",
          "valueFrom": "${SECRET_ARN}:NEXTAUTH_SECRET::"
        },
        {
          "name": "EMAIL_SERVER_HOST",
          "valueFrom": "${SECRET_ARN}:EMAIL_SERVER_HOST::"
        },
        {
          "name": "EMAIL_SERVER_PORT",
          "valueFrom": "${SECRET_ARN}:EMAIL_SERVER_PORT::"
        },
        {
          "name": "EMAIL_SERVER_USER",
          "valueFrom": "${SECRET_ARN}:EMAIL_SERVER_USER::"
        },
        {
          "name": "EMAIL_SERVER_PASSWORD",
          "valueFrom": "${SECRET_ARN}:EMAIL_SERVER_PASSWORD::"
        },
        {
          "name": "EMAIL_FROM",
          "valueFrom": "${SECRET_ARN}:EMAIL_FROM::"
        },
        {
          "name": "GOOGLE_CLIENT_ID",
          "valueFrom": "${SECRET_ARN}:GOOGLE_CLIENT_ID::"
        },
        {
          "name": "GOOGLE_CLIENT_SECRET",
          "valueFrom": "${SECRET_ARN}:GOOGLE_CLIENT_SECRET::"
        },
        {
          "name": "GITHUB_ID",
          "valueFrom": "${SECRET_ARN}:GITHUB_ID::"
        },
        {
          "name": "GITHUB_SECRET",
          "valueFrom": "${SECRET_ARN}:GITHUB_SECRET::"
        },
        {
          "name": "NODE_ENV",
          "valueFrom": "${SECRET_ARN}:NODE_ENV::"
        }
      ],
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "wget -q -O - http://localhost:${ECS_CONTAINER_PORT}/api/health || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF

# Register task definition
TASK_DEFINITION_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://"$SCRIPT_DIR/task-definition.json" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text \
  --region $AWS_REGION)

echo "Registered task definition: $TASK_DEFINITION_ARN"

# Create ECS service
aws ecs create-service \
  --cluster ${APP_NAME}-cluster \
  --service-name ${APP_NAME}-service \
  --task-definition $TASK_DEFINITION_ARN \
  --desired-count $ECS_SERVICE_COUNT \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={subnets=[$PUBLIC_SUBNET_1_ID,$PUBLIC_SUBNET_2_ID],securityGroups=[$ECS_SG_ID],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=${APP_NAME},containerPort=${ECS_CONTAINER_PORT}" \
  --health-check-grace-period-seconds 120 \
  --scheduling-strategy REPLICA \
  --deployment-configuration "maximumPercent=200,minimumHealthyPercent=100" \
  --deployment-controller "type=ECS" \
  --region $AWS_REGION

echo "Created ECS service: ${APP_NAME}-service"

# Get the load balancer DNS name
ALB_DNS_NAME=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' \
  --output text \
  --region $AWS_REGION)

echo "Application load balancer DNS name: $ALB_DNS_NAME"

# Save ALB configuration to a file
cat > "$SCRIPT_DIR/alb-config.sh" << EOF
#!/bin/bash

# ALB Configuration
export ALB_ARN=$ALB_ARN
export ALB_DNS_NAME=$ALB_DNS_NAME
export TARGET_GROUP_ARN=$TARGET_GROUP_ARN
export ALB_SG_ID=$ALB_SG_ID
export ECS_SG_ID=$ECS_SG_ID
EOF

chmod +x "$SCRIPT_DIR/alb-config.sh"

echo "ALB configuration saved to $SCRIPT_DIR/alb-config.sh"
echo "ECS resources creation completed" 
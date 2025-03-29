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

# --- Check/Create ECS Cluster ---
echo "Checking for existing ECS cluster: ${APP_NAME}-cluster..."
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "${APP_NAME}-cluster" --query 'clusters[0].status' --output text --region $AWS_REGION 2>/dev/null)

if [ $? -eq 0 ] && [ "$CLUSTER_STATUS" == "ACTIVE" ]; then
    echo "Found active ECS cluster: ${APP_NAME}-cluster"
else
    if [ $? -eq 0 ]; then # Found but not active
        echo "Found ECS cluster ${APP_NAME}-cluster, but status is $CLUSTER_STATUS. Will attempt to use."
        # Or consider exiting if status is DELETING or FAILED
        if [ "$CLUSTER_STATUS" == "INACTIVE" ]; then
            echo "Cluster is INACTIVE. Please investigate or delete manually."
            # exit 1 # Optional: exit if inactive is unacceptable
        fi
    else # Not found
        echo "ECS cluster ${APP_NAME}-cluster not found. Creating..."
        aws ecs create-cluster \
          --cluster-name ${APP_NAME}-cluster \
          --capacity-providers FARGATE FARGATE_SPOT \
          --default-capacity-provider-strategy capacityProvider=FARGATE_SPOT,weight=1 \
          --region $AWS_REGION

        if [ $? -ne 0 ]; then
            echo "Error: Failed to create ECS cluster ${APP_NAME}-cluster"
            exit 1
        fi
        echo "Created ECS cluster: ${APP_NAME}-cluster"
    fi
fi
# --- End Check/Create ECS Cluster ---

# Create application load balancer security group
# --- Check/Create ALB SG ---
ALB_SG_NAME="${APP_NAME}-alb-sg"
echo "Checking/Creating ALB Security Group: $ALB_SG_NAME..."
ALB_SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=$ALB_SG_NAME Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$ALB_SG_ID" ] || [ "$ALB_SG_ID" == "None" ]; then
    echo "ALB Security Group not found. Creating..."
    ALB_SG_ID=$(aws ec2 create-security-group \
      --group-name $ALB_SG_NAME \
      --description "Security group for ${APP_NAME} ALB" \
      --vpc-id $VPC_ID \
      --query 'GroupId' \
      --output text \
      --tag-specifications 'ResourceType=security-group,Tags=[{Key=AppName,Value='$APP_NAME'}]' \
      --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$ALB_SG_ID" ]; then echo "Failed to create ALB Security Group"; exit 1; fi
    echo "Created ALB security group: $ALB_SG_ID"

    # Allow HTTP and HTTPS traffic from anywhere (only needed when creating)
    aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $AWS_REGION
    aws ec2 authorize-security-group-ingress --group-id $ALB_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 --region $AWS_REGION
    echo "Configured ALB security group ingress rules"
else
    echo "Found existing ALB security group: $ALB_SG_ID"
fi
# --- End Check/Create ALB SG ---

# Create ECS task security group
# --- Check/Create ECS SG ---
ECS_SG_NAME="${APP_NAME}-ecs-sg"
echo "Checking/Creating ECS Security Group: $ECS_SG_NAME..."
ECS_SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=$ECS_SG_NAME Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$ECS_SG_ID" ] || [ "$ECS_SG_ID" == "None" ]; then
    echo "ECS Security Group not found. Creating..."
    ECS_SG_ID=$(aws ec2 create-security-group \
      --group-name $ECS_SG_NAME \
      --description "Security group for ${APP_NAME} ECS tasks" \
      --vpc-id $VPC_ID \
      --query 'GroupId' \
      --output text \
      --tag-specifications 'ResourceType=security-group,Tags=[{Key=AppName,Value='$APP_NAME'}]' \
      --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$ECS_SG_ID" ]; then echo "Failed to create ECS Security Group"; exit 1; fi
    echo "Created ECS task security group: $ECS_SG_ID"

    # Allow traffic from the ALB security group (only needed when creating)
    aws ec2 authorize-security-group-ingress --group-id $ECS_SG_ID --protocol tcp --port $ECS_CONTAINER_PORT --source-group $ALB_SG_ID --region $AWS_REGION
    # Allow outbound traffic (only needed when creating)
    aws ec2 authorize-security-group-egress --group-id $ECS_SG_ID --protocol all --port all --cidr 0.0.0.0/0 --region $AWS_REGION
    echo "Configured ECS task security group ingress/egress rules"
else
    echo "Found existing ECS task security group: $ECS_SG_ID"
fi
# --- End Check/Create ECS SG ---

# Authorize DB SG Ingress (Allow traffic FROM ECS SG on DB port) - Run always to ensure rule exists
echo "Authorizing access from ECS SG ($ECS_SG_ID) to DB SG ($SECURITY_GROUP_ID) on port 5432..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SECURITY_GROUP_ID" \
  --protocol tcp \
  --port 5432 \
  --source-group "$ECS_SG_ID" \
  --region $AWS_REGION || echo "WARN: Failed to add DB ingress rule (may already exist)."
# Removed strict error exit here, as duplicate rule is common

# Create application load balancer (Check if exists)
# ... (Add check/create logic similar to SGs if needed, or assume cleanup) ...
# For now, assume ALB is created if script runs multiple times, might need cleanup
echo "Checking/Creating Application Load Balancer: ${APP_NAME}-alb..."
ALB_ARN=$(aws elbv2 describe-load-balancers --names "${APP_NAME}-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" == "None" ]; then
    echo "ALB not found. Creating..."
    ALB_ARN=$(aws elbv2 create-load-balancer \
      --name ${APP_NAME}-alb \
      --subnets $PUBLIC_SUBNET_1_ID $PUBLIC_SUBNET_2_ID \
      --security-groups $ALB_SG_ID \
      --scheme internet-facing \
      --type application \
      --query 'LoadBalancers[0].LoadBalancerArn' \
      --output text \
      --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$ALB_ARN" ]; then echo "Failed to create ALB"; exit 1; fi
    echo "Created application load balancer: $ALB_ARN"
else
    echo "Found existing application load balancer: $ALB_ARN"
fi

# Get ALB Canonical Hosted Zone ID (always needed)
ALB_HOSTED_ZONE_ID=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query 'LoadBalancers[0].CanonicalHostedZoneId' \
    --output text \
    --region $AWS_REGION)
if [ -z "$ALB_HOSTED_ZONE_ID" ]; then echo "Failed to get ALB Hosted Zone ID"; exit 1; fi
echo "ALB Canonical Hosted Zone ID: $ALB_HOSTED_ZONE_ID"

# Create target group (Check if exists)
# ... (Add check/create logic) ...
echo "Checking/Creating Target Group: ${APP_NAME}-tg..."
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --names "${APP_NAME}-tg" --query 'TargetGroups[0].TargetGroupArn' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$TARGET_GROUP_ARN" ] || [ "$TARGET_GROUP_ARN" == "None" ]; then
    echo "Target group not found. Creating..."
    # --- Fix health check path with // ---
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
      --name ${APP_NAME}-tg \
      --protocol HTTP \
      --port $ECS_CONTAINER_PORT \
      --vpc-id $VPC_ID \
      --target-type ip \
      --health-check-path //api/health \
      --health-check-interval-seconds 30 \
      --health-check-timeout-seconds 5 \
      --healthy-threshold-count 2 \
      --unhealthy-threshold-count 2 \
      --query 'TargetGroups[0].TargetGroupArn' \
      --output text \
      --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$TARGET_GROUP_ARN" ]; then echo "Failed to create target group"; exit 1; fi
    echo "Created target group: $TARGET_GROUP_ARN"
else
    echo "Found existing target group: $TARGET_GROUP_ARN"
    # Optionally modify existing TG if needed
fi

# Create HTTPS listener (Check certificate first)
echo "Checking certificate validation status..."
aws acm wait certificate-validated --certificate-arn $CERTIFICATE_ARN --region $AWS_REGION
if [ $? -ne 0 ]; then
    echo "WARN: Certificate validation failed or timed out. Skipping HTTPS listener creation."
    HTTPS_LISTENER_ARN="" # Ensure it's empty if wait fails
else
    # Check if HTTPS listener exists
    echo "Checking for existing HTTPS listener..."
    HTTPS_LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query 'Listeners[?Port==`443`].ListenerArn' --output text --region $AWS_REGION 2>/dev/null)
    if [ -z "$HTTPS_LISTENER_ARN" ] || [ "$HTTPS_LISTENER_ARN" == "None" ]; then
        echo "HTTPS listener not found. Creating..."
        HTTPS_LISTENER_ARN=$(aws elbv2 create-listener \
          --load-balancer-arn $ALB_ARN \
          --protocol HTTPS \
          --port 443 \
          --certificates CertificateArn=$CERTIFICATE_ARN \
          --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
          --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
          --query 'Listeners[0].ListenerArn' \
          --output text \
          --region $AWS_REGION)
        if [ $? -ne 0 ] || [ -z "$HTTPS_LISTENER_ARN" ]; then
             echo "WARN: Failed to create HTTPS listener."
             HTTPS_LISTENER_ARN="" # Ensure empty on failure
        else
             echo "Created HTTPS listener: $HTTPS_LISTENER_ARN"
        fi
    else
        echo "Found existing HTTPS listener: $HTTPS_LISTENER_ARN"
        # Optionally modify existing listener if needed
    fi
fi

# Create HTTP listener (Check if exists)
echo "Checking for existing HTTP listener..."
HTTP_LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query 'Listeners[?Port==`80`].ListenerArn' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$HTTP_LISTENER_ARN" ] || [ "$HTTP_LISTENER_ARN" == "None" ]; then
    echo "HTTP listener not found. Creating..."
    # Create redirect if HTTPS exists, otherwise forward
    if [ -n "$HTTPS_LISTENER_ARN" ]; then
      # --- Use JSON format for redirect action ---
      ACTION_JSON='[
        {
          "Type": "redirect",
          "RedirectConfig": {
            "Protocol": "HTTPS",
            "Port": "443",
            "Host": "#{host}",
            "Path": "/#{path}",
            "Query": "#{query}",
            "StatusCode": "HTTP_301"
          }
        }
      ]'
      LISTENER_TYPE_MSG="(redirect to HTTPS)"
    else
      # --- Use JSON format for forward action ---
      ACTION_JSON='[
        {
          "Type": "forward",
          "TargetGroupArn": "'$TARGET_GROUP_ARN'"
        }
      ]'
      LISTENER_TYPE_MSG="(forward to target)"
    fi
    HTTP_LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn $ALB_ARN \
        --protocol HTTP \
        --port 80 \
        --default-actions "$ACTION_JSON" \
        --query 'Listeners[0].ListenerArn' \
        --output text \
        --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$HTTP_LISTENER_ARN" ]; then
         echo "WARN: Failed to create HTTP listener."
         HTTP_LISTENER_ARN="" # Ensure empty on failure
    else
         echo "Created HTTP listener $LISTENER_TYPE_MSG: $HTTP_LISTENER_ARN"
    fi
else
     echo "Found existing HTTP listener: $HTTP_LISTENER_ARN"
     # Optionally modify existing listener if needed (e.g., change action if HTTPS was created later)
fi

# --- Add SSM Policy Creation/Retrieval ---
SSM_POLICY_NAME="${APP_NAME}-ssm-parameter-access-policy"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_DOCUMENT=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "ssm:GetParameters",
            "Resource": "arn:aws:ssm:${AWS_REGION}:${ACCOUNT_ID}:parameter/${APP_NAME}-*"
        }
    ]
}
EOF
)

echo "Checking/Creating IAM Policy for SSM access: $SSM_POLICY_NAME..."
# Attempt to get the policy ARN if it exists
SSM_POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$SSM_POLICY_NAME'].Arn" --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$SSM_POLICY_ARN" ] || [ "$SSM_POLICY_ARN" == "None" ]; then
    echo "SSM Policy not found. Creating..."
    CREATE_POLICY_OUTPUT=$(aws iam create-policy \\
      --policy-name $SSM_POLICY_NAME \\
      --policy-document "$POLICY_DOCUMENT" \\
      --description "Policy granting access to ${APP_NAME} SSM parameters" \\
      --query 'Policy.Arn' \\
      --output text \\
      --region $AWS_REGION)

    if [ $? -ne 0 ] || [ -z "$CREATE_POLICY_OUTPUT" ]; then
        echo "Error: Failed to create IAM policy $SSM_POLICY_NAME"
        exit 1
    fi
    SSM_POLICY_ARN=$CREATE_POLICY_OUTPUT
    echo "Created IAM policy: $SSM_POLICY_NAME (ARN: $SSM_POLICY_ARN)"
else
    echo "Found existing IAM policy: $SSM_POLICY_NAME (ARN: $SSM_POLICY_ARN)"
fi
# --- End SSM Policy Creation/Retrieval ---

# Create IAM execution role for ECS tasks (Check if exists)
ECS_EXECUTION_ROLE_NAME="${APP_NAME}-ecs-execution-role"
echo "Checking/Creating IAM Execution Role: $ECS_EXECUTION_ROLE_NAME..."
ECS_EXECUTION_ROLE_ARN=$(aws iam get-role --role-name $ECS_EXECUTION_ROLE_NAME --query 'Role.Arn' --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$ECS_EXECUTION_ROLE_ARN" ] || [ "$ECS_EXECUTION_ROLE_ARN" == "None" ]; then
    echo "IAM Execution Role not found. Creating..."
    # Define Assume Role Policy JSON directly as a string
    ASSUME_ROLE_POLICY_DOC='{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": { "Service": "ecs-tasks.amazonaws.com" },
          "Action": "sts:AssumeRole"
        }
      ]
    }'
    # Create IAM execution role, passing policy as string
    ROLE_CREATE_OUTPUT=$(aws iam create-role \
      --role-name $ECS_EXECUTION_ROLE_NAME \
      --assume-role-policy-document "$ASSUME_ROLE_POLICY_DOC" \
      --query 'Role.Arn' \
      --output text \
      --region $AWS_REGION)
    # Explicit error check after create-role
    if [ $? -ne 0 ] || [ -z "$ROLE_CREATE_OUTPUT" ]; then
        echo "Error: Failed to create IAM execution role $ECS_EXECUTION_ROLE_NAME"
        exit 1
    fi
    ECS_EXECUTION_ROLE_ARN=$ROLE_CREATE_OUTPUT
    echo "Created IAM execution role: $ECS_EXECUTION_ROLE_NAME (ARN: $ECS_EXECUTION_ROLE_ARN)"

    # Policies only need attaching when role is first created
    # Attach policies
    aws iam attach-role-policy --role-name $ECS_EXECUTION_ROLE_NAME --policy-arn $SSM_POLICY_ARN --region $AWS_REGION
    aws iam attach-role-policy --role-name $ECS_EXECUTION_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy --region $AWS_REGION
    echo "Attached policies to new role."
    # Add a small delay to allow role/policy propagation
    sleep 10

else
    echo "Found existing IAM execution role: $ECS_EXECUTION_ROLE_NAME (ARN: $ECS_EXECUTION_ROLE_ARN)"
    # Optionally ensure policies are attached even if role exists
    aws iam attach-role-policy --role-name $ECS_EXECUTION_ROLE_NAME --policy-arn $SSM_POLICY_ARN --region $AWS_REGION || echo "WARN: Failed to attach SSM policy (may already be attached)"
    aws iam attach-role-policy --role-name $ECS_EXECUTION_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy --region $AWS_REGION || echo "WARN: Failed to attach standard ECS policy (may already be attached)"
fi

# Remove temporary file if it exists from previous versions
rm -f "$SCRIPT_DIR/assume-role-policy.json"

# Create task definition JSON content as a variable
echo "Preparing Task Definition JSON content..."
TASK_DEFINITION_JSON=$(cat <<EOF
{
  "family": "${APP_NAME}-task",
  "networkMode": "awsvpc",
  "executionRoleArn": "${ECS_EXECUTION_ROLE_ARN}",
  "taskRoleArn": "${ECS_EXECUTION_ROLE_ARN}",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "${ECS_TASK_CPU}",
  "memory": "${ECS_TASK_MEMORY}",
  "containerDefinitions": [
    {
      "name": "${ECS_CONTAINER_NAME}",
      "image": "${REPOSITORY_URI}:latest",
      "essential": true,
      "portMappings": [ { "containerPort": ${ECS_CONTAINER_PORT}, "protocol": "tcp" } ],
      "logConfiguration": { "logDriver": "awslogs", "options": { "awslogs-group": "/ecs/${APP_NAME}", "awslogs-region": "${AWS_REGION}", "awslogs-stream-prefix": "ecs", "awslogs-create-group": "true" } },
      "secrets": [
         {"name": "DATABASE_URL", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-DATABASE_URL"},
         {"name": "DIRECT_URL", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-DIRECT_URL"},
         {"name": "NEXT_PUBLIC_APP_URL", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-NEXT_PUBLIC_APP_URL"},
         {"name": "NEXTAUTH_URL", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-NEXTAUTH_URL"},
         {"name": "NEXTAUTH_SECRET", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-NEXTAUTH_SECRET"},
         {"name": "EMAIL_SERVER_HOST", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-EMAIL_SERVER_HOST"},
         {"name": "EMAIL_SERVER_PORT", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-EMAIL_SERVER_PORT"},
         {"name": "EMAIL_SERVER_USER", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-EMAIL_SERVER_USER"},
         {"name": "EMAIL_SERVER_PASSWORD", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-EMAIL_SERVER_PASSWORD"},
         {"name": "EMAIL_FROM", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-EMAIL_FROM"},
         {"name": "GOOGLE_CLIENT_ID", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-GOOGLE_CLIENT_ID"},
         {"name": "GOOGLE_CLIENT_SECRET", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-GOOGLE_CLIENT_SECRET"},
         {"name": "GITHUB_ID", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-GITHUB_ID"},
         {"name": "GITHUB_SECRET", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-GITHUB_SECRET"},
         {"name": "NODE_ENV", "valueFrom": "${SECRET_PARAMETER_NAME_PREFIX}-NODE_ENV"}
       ],
      "healthCheck": { "command": [ "CMD-SHELL", "wget -q -O - http://localhost:${ECS_CONTAINER_PORT}/api/health || exit 1" ], "interval": 30, "timeout": 5, "retries": 3, "startPeriod": 60 }
    }
  ]
}
EOF
)
# Remove temporary file if it exists from previous versions
rm -f "$SCRIPT_DIR/task-definition.json"

# Register task definition, passing JSON as string
echo "Registering Task Definition..."
TASK_DEFINITION_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$TASK_DEFINITION_JSON" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text \
  --region $AWS_REGION)

if [ $? -ne 0 ] || [ -z "$TASK_DEFINITION_ARN" ]; then echo "Failed to register task definition"; exit 1; fi

echo "Registered task definition: $TASK_DEFINITION_ARN"

# Create ECS service (Check if exists)
# ... (Add check/create logic) ...
echo "Checking/Creating ECS Service: ${ECS_SERVICE_NAME}..."
SERVICE_EXISTS=$(aws ecs describe-services --cluster ${ECS_CLUSTER_NAME} --services ${ECS_SERVICE_NAME} --query 'services[?status!=`INACTIVE`].serviceName' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$SERVICE_EXISTS" ] || [ "$SERVICE_EXISTS" == "None" ]; then
    echo "ECS Service not found. Creating..."
    aws ecs create-service \
      --cluster ${ECS_CLUSTER_NAME} \
      --service-name ${ECS_SERVICE_NAME} \
      --task-definition $TASK_DEFINITION_ARN \
      --desired-count $ECS_SERVICE_COUNT \
      --launch-type FARGATE \
      --platform-version LATEST \
      --network-configuration "awsvpcConfiguration={subnets=[$PRIVATE_SUBNET_1_ID,$PRIVATE_SUBNET_2_ID],securityGroups=[$ECS_SG_ID],assignPublicIp=DISABLED}" \
      --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=${ECS_CONTAINER_NAME},containerPort=${ECS_CONTAINER_PORT}" \
      --health-check-grace-period-seconds 120 \
      --scheduling-strategy REPLICA \
      --deployment-configuration "maximumPercent=200,minimumHealthyPercent=100" \
      --deployment-controller "type=ECS" \
      --region $AWS_REGION \
      --tags key=AppName,value=$APP_NAME
    if [ $? -ne 0 ]; then echo "Failed to create ECS Service"; exit 1; fi
    echo "Created ECS service: ${ECS_SERVICE_NAME}"
else
    echo "Found existing ECS service: $SERVICE_EXISTS"
    # --- Add update-service logic --- 
    echo "Updating service $SERVICE_EXISTS to use task definition $TASK_DEFINITION_ARN..."
    aws ecs update-service \
      --cluster ${ECS_CLUSTER_NAME} \
      --service ${SERVICE_EXISTS} \
      --task-definition $TASK_DEFINITION_ARN \
      --force-new-deployment \
      --region $AWS_REGION
    if [ $? -ne 0 ]; then echo "WARN: Failed to update ECS Service $SERVICE_EXISTS"; fi # Don't exit, just warn
    # --- End update-service logic ---
fi

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
export ALB_HOSTED_ZONE_ID=$ALB_HOSTED_ZONE_ID
export ALB_SG_ID=$ALB_SG_ID
export ECS_SG_ID=$ECS_SG_ID
EOF

chmod +x "$SCRIPT_DIR/alb-config.sh"

echo "ALB configuration saved to $SCRIPT_DIR/alb-config.sh"

# --- NEW: Save Target Group ARN ---
# We need this for the cleanup script
echo "Updating alb-config.sh with Target Group ARN..."
if grep -q "export TARGET_GROUP_ARN=" "$SCRIPT_DIR/alb-config.sh"; then
    sed -i "s|^export TARGET_GROUP_ARN=.*$|export TARGET_GROUP_ARN=\"$TARGET_GROUP_ARN\"|" "$SCRIPT_DIR/alb-config.sh"
else
    echo "export TARGET_GROUP_ARN=\"$TARGET_GROUP_ARN\"" >> "$SCRIPT_DIR/alb-config.sh"
fi
# --- End Save Target Group ARN ---

# --- Add SSM Policy Creation/Retrieval ---
echo "Updating secrets-config.sh with SSM Policy ARN..."
# Use grep to check if the line already exists, add if not
if ! grep -q "export SSM_POLICY_ARN=" "$SCRIPT_DIR/secrets-config.sh"; then
  echo "export SSM_POLICY_ARN=\"$SSM_POLICY_ARN\"" >> "$SCRIPT_DIR/secrets-config.sh"
  echo "SSM_POLICY_ARN added to secrets-config.sh"
else
  # Optionally update if it exists but is different (more complex, skip for now)
  echo "SSM_POLICY_ARN already exists in secrets-config.sh"
fi
# --- End saving SSM Policy ARN ---

echo "ECS resources creation completed" 
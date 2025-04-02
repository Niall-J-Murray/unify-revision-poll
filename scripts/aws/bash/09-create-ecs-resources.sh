#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"

# Source all the configuration files
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$CONFIG_DIR/vpc-config.sh"
source "$CONFIG_DIR/rds-config.sh"
source "$CONFIG_DIR/ecr-config.sh"
source "$CONFIG_DIR/certificate-config.sh"
source "$CONFIG_DIR/secrets-config.sh"

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

# --- Check/Create ECS Execution Role ---
ECS_EXECUTION_ROLE_NAME="${APP_NAME}-ecs-execution-role"
echo "Checking/Creating ECS Execution Role: $ECS_EXECUTION_ROLE_NAME..."
ECS_EXECUTION_ROLE_ARN=$(aws iam get-role --role-name $ECS_EXECUTION_ROLE_NAME --query 'Role.Arn' --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$ECS_EXECUTION_ROLE_ARN" ] || [ "$ECS_EXECUTION_ROLE_ARN" == "None" ]; then
    echo "Execution role not found. Creating..."
    # Create trust policy file
    ASSUME_ROLE_POLICY_DOC=$(cat <<EOF
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
)
    ECS_EXECUTION_ROLE_ARN=$(aws iam create-role \
      --role-name $ECS_EXECUTION_ROLE_NAME \
      --assume-role-policy-document "$ASSUME_ROLE_POLICY_DOC" \
      --description "Role for ECS tasks to access AWS services" \
      --query 'Role.Arn' \
      --output text \
      --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$ECS_EXECUTION_ROLE_ARN" ]; then echo "Failed to create execution role"; exit 1; fi
    echo "Created execution role: $ECS_EXECUTION_ROLE_ARN"

    # Attach the standard ECS Task Execution Role Policy
    echo "Attaching standard policy..."
    aws iam attach-role-policy \
      --role-name $ECS_EXECUTION_ROLE_NAME \
      --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
      --region $AWS_REGION
    if [ $? -ne 0 ]; then echo "Failed to attach standard policy"; exit 1; fi

else
    echo "Found existing execution role: $ECS_EXECUTION_ROLE_ARN"
    # Ensure standard policy is attached even if role exists
    if ! aws iam list-attached-role-policies --role-name $ECS_EXECUTION_ROLE_NAME --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy']" --output text --region $AWS_REGION | grep -q .; then
        echo "Attaching standard policy to existing role..."
        aws iam attach-role-policy \
            --role-name $ECS_EXECUTION_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy \
            --region $AWS_REGION
        if [ $? -ne 0 ]; then echo "Failed to attach standard policy"; exit 1; fi
    fi
fi

# Remove temporary file if it exists from previous versions
rm -f "$SCRIPT_DIR/assume-role-policy.json"

# Check/Create SSM Parameter Access Policy
SSM_POLICY_NAME="${APP_NAME}-ssm-parameter-access-policy"
echo "Checking/Creating IAM policy for SSM access: $SSM_POLICY_NAME..."

# Use hyphenated name prefix for policy resource
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SSM_PARAMETER_ARN_PATTERN="arn:aws:ssm:${AWS_REGION}:${ACCOUNT_ID}:parameter/${APP_NAME}-*"

# Check if policy exists
SSM_POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$SSM_POLICY_NAME'].Arn" --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$SSM_POLICY_ARN" ] || [ "$SSM_POLICY_ARN" == "None" ]; then
  echo "SSM policy not found. Creating..."
  POLICY_DOCUMENT=$(cat <<-EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "ssm:GetParameters",
            "Resource": "$SSM_PARAMETER_ARN_PATTERN"
        }
    ]
}
EOF
)
  SSM_POLICY_ARN=$(aws iam create-policy \
    --policy-name $SSM_POLICY_NAME \
    --policy-document "$POLICY_DOCUMENT" \
    --description "Policy granting access to ${APP_NAME} SSM parameters named ${APP_NAME}-*" \
    --query 'Policy.Arn' \
    --output text \
    --region $AWS_REGION)
  if [ $? -ne 0 ] || [ -z "$SSM_POLICY_ARN" ]; then echo "Error: Failed to create SSM policy"; exit 1; fi
  echo "Created SSM policy: $SSM_POLICY_ARN"
else
  echo "SSM policy already exists: $SSM_POLICY_ARN"
fi

# Attach SSM Policy to Execution Role
echo "Checking/Attaching SSM policy ($SSM_POLICY_ARN) to role ($ECS_EXECUTION_ROLE_NAME)..."
POLICY_ATTACHED=$(aws iam list-attached-role-policies --role-name $ECS_EXECUTION_ROLE_NAME --query "AttachedPolicies[?PolicyArn=='$SSM_POLICY_ARN'].PolicyArn" --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$POLICY_ATTACHED" ] || [ "$POLICY_ATTACHED" == "None" ]; then
  echo "Attaching SSM policy to execution role..."
  aws iam attach-role-policy \
    --role-name $ECS_EXECUTION_ROLE_NAME \
    --policy-arn $SSM_POLICY_ARN \
    --region $AWS_REGION
  if [ $? -ne 0 ]; then echo "Error: Failed to attach SSM policy to execution role"; exit 1; fi
  echo "Successfully attached SSM policy to execution role"
else
  echo "SSM policy is already attached to the execution role"
fi

# Save/Update SSM Policy ARN in secrets-config.sh
echo "Updating secrets-config.sh with SSM Policy ARN..."
SECRETS_CONFIG_FILE="$CONFIG_DIR/secrets-config.sh"
TEMP_SECRETS_CONFIG="$CONFIG_DIR/secrets-config.sh.tmp"
# Create or overwrite temp file
echo "#!/bin/bash" > "$TEMP_SECRETS_CONFIG"
# Preserve existing Secret Parameter Name Prefix
if [ -f "$SECRETS_CONFIG_FILE" ] && grep -q "export SECRET_PARAMETER_NAME_PREFIX=" "$SECRETS_CONFIG_FILE"; then
    grep "export SECRET_PARAMETER_NAME_PREFIX=" "$SECRETS_CONFIG_FILE" >> "$TEMP_SECRETS_CONFIG"
elif [ -n "$PARAM_NAME_PREFIX" ]; then # Fallback if grep failed but var exists
    echo "export SECRET_PARAMETER_NAME_PREFIX=\\"$PARAM_NAME_PREFIX\\"" >> "$TEMP_SECRETS_CONFIG"
fi
# Add/Update SSM Policy ARN
echo "# SSM Policy ARN" >> "$TEMP_SECRETS_CONFIG"
echo "export SSM_POLICY_ARN=\\"$SSM_POLICY_ARN\\"" >> "$TEMP_SECRETS_CONFIG"
# Make executable and replace original
chmod +x "$TEMP_SECRETS_CONFIG"
mv "$TEMP_SECRETS_CONFIG" "$SECRETS_CONFIG_FILE"
echo "SSM_POLICY_ARN updated in $SECRETS_CONFIG_FILE"

# --- Check/Create ECS Task Definition ---
# Source configs again to ensure necessary variables are loaded (like LATEST_PUSHED_TAG)
[ -f "$CONFIG_DIR/secrets-config.sh" ] && source "$CONFIG_DIR/secrets-config.sh"
[ -f "$CONFIG_DIR/ecr-config.sh" ] && source "$CONFIG_DIR/ecr-config.sh" # Source ECR config
if [ -z "$SECRET_PARAMETER_NAME_PREFIX" ]; then echo "Error: SECRET_PARAMETER_NAME_PREFIX not found in $CONFIG_DIR/secrets-config.sh."; exit 1; fi
if [ -z "$REPOSITORY_URI" ]; then echo "Error: REPOSITORY_URI not found in $CONFIG_DIR/ecr-config.sh."; exit 1; fi
if [ -z "$LATEST_PUSHED_TAG" ]; then echo "Error: LATEST_PUSHED_TAG not found in $CONFIG_DIR/ecr-config.sh. Run 06-build-push-docker.sh first."; exit 1; fi

# --- FIX: Explicitly get AWS Account ID before creating Task Definition JSON --- 
echo "Retrieving AWS Account ID..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region $AWS_REGION)
if [ -z "$AWS_ACCOUNT_ID" ]; then 
    echo "Error: Could not determine AWS Account ID using sts get-caller-identity."
    exit 1
fi
echo "Using Account ID: $AWS_ACCOUNT_ID"
# --- END FIX ---

# Create task definition JSON content as a variable
echo "Preparing Task Definition JSON content using image tag: $LATEST_PUSHED_TAG..."
TASK_DEFINITION_JSON=$(cat <<EOF
{
  "family": "${APP_NAME}-task",
  "networkMode": "awsvpc",
  "executionRoleArn": "${ECS_EXECUTION_ROLE_ARN}",
  # taskRoleArn defines permissions for the application code itself.
  # Using the execution role ARN here grants the application the same permissions 
  # needed for setup (ECR pull, CW Logs, SSM GetParameters).
  # If your application needs specific AWS permissions (e.g., S3 access), 
  # create a separate IAM role with *only* those permissions and specify its ARN here.
  "taskRoleArn": "${ECS_EXECUTION_ROLE_ARN}",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "${ECS_TASK_CPU}",
  "memory": "${ECS_TASK_MEMORY}",
  "containerDefinitions": [
    {
      "name": "${ECS_CONTAINER_NAME}",
      "image": "${REPOSITORY_URI}:${LATEST_PUSHED_TAG}",
      "essential": true,
      "portMappings": [ { "containerPort": ${ECS_CONTAINER_PORT}, "protocol": "tcp" } ],
      "logConfiguration": { "logDriver": "awslogs", "options": { "awslogs-group": "/ecs/${APP_NAME}", "awslogs-region": "${AWS_REGION}", "awslogs-stream-prefix": "ecs", "awslogs-create-group": "true" } },
      "secrets": [
         {"name": "DATABASE_URL", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-DATABASE_URL"},
         {"name": "DIRECT_URL", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-DIRECT_URL"},
         {"name": "NEXT_PUBLIC_APP_URL", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-NEXT_PUBLIC_APP_URL"},
         {"name": "NEXTAUTH_URL", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-NEXTAUTH_URL"},
         {"name": "NEXTAUTH_SECRET", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-NEXTAUTH_SECRET"},
         {"name": "EMAIL_SERVER_HOST", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-EMAIL_SERVER_HOST"},
         {"name": "EMAIL_SERVER_PORT", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-EMAIL_SERVER_PORT"},
         {"name": "EMAIL_SERVER_USER", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-EMAIL_SERVER_USER"},
         {"name": "EMAIL_SERVER_PASSWORD", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-EMAIL_SERVER_PASSWORD"},
         {"name": "EMAIL_FROM", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-EMAIL_FROM"},
         {"name": "GOOGLE_CLIENT_ID", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-GOOGLE_CLIENT_ID"},
         {"name": "GOOGLE_CLIENT_SECRET", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-GOOGLE_CLIENT_SECRET"},
         {"name": "GITHUB_ID", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-GITHUB_ID"},
         {"name": "GITHUB_SECRET", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-GITHUB_SECRET"},
         {"name": "NODE_ENV", "valueFrom": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/${SECRET_PARAMETER_NAME_PREFIX}-NODE_ENV"}
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
ALB_CONFIG_FILE="$CONFIG_DIR/alb-config.sh"
cat > "$ALB_CONFIG_FILE" << EOF
#!/bin/bash

# ALB Configuration
export ALB_ARN=$ALB_ARN
export ALB_DNS_NAME=$ALB_DNS_NAME
export TARGET_GROUP_ARN=$TARGET_GROUP_ARN
export ALB_HOSTED_ZONE_ID=$ALB_HOSTED_ZONE_ID
export ALB_SG_ID=$ALB_SG_ID
export ECS_SG_ID=$ECS_SG_ID
EOF

chmod +x "$ALB_CONFIG_FILE"

echo "ALB configuration saved to $ALB_CONFIG_FILE"

# --- NEW: Save Target Group ARN ---
# We need this for the cleanup script
echo "Updating $ALB_CONFIG_FILE with Target Group ARN..."
if grep -q "export TARGET_GROUP_ARN=" "$ALB_CONFIG_FILE"; then
    sed -i "s|^export TARGET_GROUP_ARN=.*$|export TARGET_GROUP_ARN=\\"$TARGET_GROUP_ARN\\"|" "$ALB_CONFIG_FILE"
else
    echo "export TARGET_GROUP_ARN=\\"$TARGET_GROUP_ARN\\"" >> "$ALB_CONFIG_FILE"
fi
# --- End Save Target Group ARN ---

echo "ECS resources creation completed" 
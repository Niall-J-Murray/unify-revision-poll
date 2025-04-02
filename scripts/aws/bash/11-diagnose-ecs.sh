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
# Attempt to load ECS Execution Role ARN if ecs-config.sh exists (assuming it would be in config/ too)
[ -f "$CONFIG_DIR/ecs-config.sh" ] && source "$CONFIG_DIR/ecs-config.sh" 

echo "Diagnosing ECS task issues for '$APP_NAME'..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure required tools are installed
if ! command_exists aws || ! command_exists jq; then
    echo "Error: Required tools (aws cli, jq) are not installed or not in PATH."
    exit 1
fi

# --- Load ECS Execution Role ARN from Task Definition (more reliable if config is missing) ---
# Try loading dynamically first if family name is set
if [ -n "$ECS_TASK_FAMILY" ]; then
    ECS_EXECUTION_ROLE_ARN_DYNAMIC=$(aws ecs describe-task-definition --task-definition $ECS_TASK_FAMILY --query 'taskDefinition.executionRoleArn' --output text --region $AWS_REGION 2>/dev/null)
    if [ -n "$ECS_EXECUTION_ROLE_ARN_DYNAMIC" ]; then
        ECS_EXECUTION_ROLE_ARN=$ECS_EXECUTION_ROLE_ARN_DYNAMIC
        echo "Dynamically loaded ECS_EXECUTION_ROLE_ARN: $ECS_EXECUTION_ROLE_ARN"
    elif [ -z "$ECS_EXECUTION_ROLE_ARN" ]; then # Only warn if dynamic load failed AND config load failed
         echo "Warning: Could not dynamically load ECS_EXECUTION_ROLE_ARN from task definition '$ECS_TASK_FAMILY' and not found in config."
    fi
fi

# --- Variable Checks ---
echo "1. Checking Essential Variables..."
# Check SSM_POLICY_ARN from secrets-config.sh
[ -z "$SSM_POLICY_ARN" ] && echo "   Warning: SSM_POLICY_ARN not found in secrets-config.sh, attempting to find dynamically..." && SSM_POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName==\`${APP_NAME}-ssm-parameter-access-policy\`].Arn" --output text --region $AWS_REGION 2>/dev/null)

REQUIRED_VARS=("AWS_REGION" "APP_NAME" "VPC_ID" "PRIVATE_SUBNET_1_ID" "PRIVATE_SUBNET_2_ID" "VPC_SECURITY_GROUP_ID" "ECS_CLUSTER_NAME" "ECS_SERVICE_NAME" "ECS_TASK_FAMILY" "ECS_EXECUTION_ROLE_ARN" "SECRET_PARAMETER_NAME_PREFIX" "SSM_POLICY_ARN") 
ERROR=false
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "   Error: Variable '$var' is not set. Check 01-setup-variables.sh and other config files (vpc-config.sh, secrets-config.sh, ecs-config.sh)."
        ERROR=true
    else
         echo "   OK: $var is set."
    fi
done
if [ "$ERROR" = true ]; then 
    echo "Exiting due to missing essential variables."
    exit 1; 
fi

# --- VPC Endpoint Check ---
echo "\n2. Checking VPC Endpoints (for private subnets)..."
SERVICES_TO_CHECK=("ssm" "ssmmessages" "ecr.api" "ecr.dkr" "logs")
ENDPOINT_ERROR=false
for service in "${SERVICES_TO_CHECK[@]}"; do
    endpoint_name="${APP_NAME}-${service//./-}-endpoint"
    echo -n "   Checking $service ($endpoint_name)... "
    ENDPOINT_ID=$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC_ID Name=service-name,Values="com.amazonaws.${AWS_REGION}.${service}" Name=tag:Name,Values="$endpoint_name" --query 'VpcEndpoints[?State==`available`].VpcEndpointId' --output text --region $AWS_REGION 2>/dev/null)
    if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" == "None" ]; then
        echo "NOT FOUND or not available. -> Run '03-setup-networking.sh'"
        ENDPOINT_ERROR=true
    else
        ENDPOINT_DETAILS=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $ENDPOINT_ID --query "VpcEndpoints[0].{Subnets:SubnetIds, SGs:Groups[*].GroupId}" --output json --region $AWS_REGION)
        echo "OK ($ENDPOINT_ID) Details: $ENDPOINT_DETAILS"
    fi
done
# S3 Gateway endpoint check
echo -n "   Checking s3 (gateway endpoint)... "
ENDPOINT_ID=$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC_ID Name=service-name,Values="com.amazonaws.${AWS_REGION}.s3" --query 'VpcEndpoints[?VpcEndpointType==`Gateway` && State==`available`].VpcEndpointId\' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" == "None" ]; then
    echo "NOT FOUND or not available. -> Run '03-setup-networking.sh'"
    ENDPOINT_ERROR=true
else
     ENDPOINT_DETAILS=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $ENDPOINT_ID --query "VpcEndpoints[0].{RouteTables:RouteTableIds}" --output json --region $AWS_REGION)
     echo "OK ($ENDPOINT_ID) Details: $ENDPOINT_DETAILS"
fi
if [ "$ENDPOINT_ERROR" = true ]; then echo "   Error: Missing required VPC endpoints for private subnet communication."; fi

# --- ECS Task Definition Check ---
echo "\n3. Checking ECS Task Definition ($ECS_TASK_FAMILY)..."
TASK_DEF_DETAILS=$(aws ecs describe-task-definition --task-definition $ECS_TASK_FAMILY --include TAGS --region $AWS_REGION 2>/dev/null)
TASK_DEF_ARN_ACTUAL="" # Initialize
if [ $? -ne 0 ]; then
    echo "   Error: Failed to describe task definition '$ECS_TASK_FAMILY'. Does it exist? -> Check 09-create-ecs-resources.sh"
else
    echo "   OK: Task definition found."
    TASK_DEF_ARN_ACTUAL=$(echo "$TASK_DEF_DETAILS" | jq -r '.taskDefinition.taskDefinitionArn')
    echo "      Full ARN: $TASK_DEF_ARN_ACTUAL"
    NETWORK_MODE=$(echo "$TASK_DEF_DETAILS" | jq -r '.taskDefinition.networkMode')
    echo "      Network Mode: $NETWORK_MODE"
    if [ "$NETWORK_MODE" != "awsvpc" ]; then echo "      Warning: Network mode is not 'awsvpc'. Fargate requires 'awsvpc' mode. -> Check 09-create-ecs-resources.sh"; fi
    EXECUTION_ROLE_ARN_IN_DEF=$(echo "$TASK_DEF_DETAILS" | jq -r '.taskDefinition.executionRoleArn')
    echo "      Execution Role ARN: $EXECUTION_ROLE_ARN_IN_DEF"
    if [ "$EXECUTION_ROLE_ARN_IN_DEF" != "$ECS_EXECUTION_ROLE_ARN" ]; then echo "      Warning: Execution role ARN in definition differs from config variable ($ECS_EXECUTION_ROLE_ARN). -> Check 09-create-ecs-resources.sh"; fi
    CONTAINER_DEFS=$(echo "$TASK_DEF_DETAILS" | jq '.taskDefinition.containerDefinitions')
    if [[ -z "$CONTAINER_DEFS" || "$CONTAINER_DEFS" == "[]" || "$CONTAINER_DEFS" == "null" ]]; then echo "      Error: No container definitions found."; else echo "      OK: Found container definition(s)."
        # Check Secrets 
        echo "$CONTAINER_DEFS" | jq -c '.[] | select(.secrets) | .secrets[]?' | while read secret; do
             SECRET_ARN=$(echo $secret | jq -r '.valueFrom')
             SECRET_NAME=$(echo $secret | jq -r '.name')
             echo -n "         Checking secret '$SECRET_NAME' source '$SECRET_ARN'... "
             # Use parameter path prefix for check
             EXPECTED_PREFIX="arn:aws:ssm:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):parameter/${SECRET_PARAMETER_NAME_PREFIX}-"
             if [[ "$SECRET_ARN" == ${EXPECTED_PREFIX}* ]]; then 
                 echo "OK (Matches prefix pattern '${SECRET_PARAMETER_NAME_PREFIX}-*')"
             else 
                 echo "WARNING (Parameter ARN '$SECRET_ARN' does not match expected prefix pattern '${SECRET_PARAMETER_NAME_PREFIX}-*')"
             fi
        done
    fi
fi

# --- ECS Service Check ---
echo "\n4. Checking ECS Service ($ECS_SERVICE_NAME)..."
SERVICE_DETAILS=$(aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --include TAGS --region $AWS_REGION 2>/dev/null)
if [ $? -ne 0 ]; then echo "   Error: Failed to describe service '$ECS_SERVICE_NAME' in cluster '$ECS_CLUSTER_NAME'. Does it exist? -> Check 09-create-ecs-resources.sh"; else echo "   OK: Service found."
    STATUS=$(echo "$SERVICE_DETAILS" | jq -r '.services[0].status')
    DESIRED_COUNT=$(echo "$SERVICE_DETAILS" | jq -r '.services[0].desiredCount')
    RUNNING_COUNT=$(echo "$SERVICE_DETAILS" | jq -r '.services[0].runningCount')
    PENDING_COUNT=$(echo "$SERVICE_DETAILS" | jq -r '.services[0].pendingCount')
    TASK_DEF_IN_SERVICE=$(echo "$SERVICE_DETAILS" | jq -r '.services[0].taskDefinition')
    echo "      Status: $STATUS, Desired: $DESIRED_COUNT, Running: $RUNNING_COUNT, Pending: $PENDING_COUNT"
    echo "      Task Definition: $TASK_DEF_IN_SERVICE"
    if [ -n "$TASK_DEF_ARN_ACTUAL" ] && [ "$TASK_DEF_IN_SERVICE" != "$TASK_DEF_ARN_ACTUAL" ]; then echo "      Warning: Service is using a different task definition ARN than the latest found in describe-task-definition. -> Check 09-create-ecs-resources.sh or run 10-finalize-deployment.sh"; fi
    SERVICE_NETWORK_CONFIG=$(echo "$SERVICE_DETAILS" | jq -r '.services[0].networkConfiguration.awsvpcConfiguration')
    SERVICE_SUBNETS=$(echo "$SERVICE_NETWORK_CONFIG" | jq -r '.subnets | join(" ")')
    SERVICE_SGS=$(echo "$SERVICE_NETWORK_CONFIG" | jq -r '.securityGroups | join(" ")')
    PUBLIC_IP_ENABLED=$(echo "$SERVICE_NETWORK_CONFIG" | jq -r '.assignPublicIp')
    echo "      Subnets: $SERVICE_SUBNETS"
    echo "      Security Groups: $SERVICE_SGS"
    echo "      Assign Public IP: $PUBLIC_IP_ENABLED"
    if [[ "$SERVICE_SUBNETS" != *"$PRIVATE_SUBNET_1_ID"* || "$SERVICE_SUBNETS" != *"$PRIVATE_SUBNET_2_ID"* ]]; then echo "      Warning: Service subnets do not seem to match the configured private subnets ($PRIVATE_SUBNET_1_ID, $PRIVATE_SUBNET_2_ID). -> Check 09-create-ecs-resources.sh"; fi
    # Check if service SGs include the main VPC SG (or others like ALB/ECS specific SGs if they exist)
    if [ -n "$VPC_SECURITY_GROUP_ID" ] && [[ "$SERVICE_SGS" != *"$VPC_SECURITY_GROUP_ID"* ]]; then echo "      Warning: Service security groups do not seem to include the main VPC security group ($VPC_SECURITY_GROUP_ID). -> Check 09-create-ecs-resources.sh"; fi
    if [ "$PUBLIC_IP_ENABLED" == "ENABLED" ]; then echo "      Warning: Service has Assign Public IP ENABLED. Should be DISABLED for private subnets. -> Check 09-create-ecs-resources.sh"; fi

    echo "      Service Events (Last 5):"
    aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --query "services[0].events | sort_by(@, &createdAt)[-5:]" --output table --region $AWS_REGION

fi

# --- IAM Role/Policy Check ---
echo "\n5. Checking IAM Execution Role Permissions ($ECS_EXECUTION_ROLE_ARN)..."
ROLE_NAME=$(basename $ECS_EXECUTION_ROLE_ARN)
aws iam get-role --role-name $ROLE_NAME --region $AWS_REGION > /dev/null 2>&1
if [ $? -ne 0 ]; then echo "   Error: Execution Role '$ROLE_NAME' not found. -> Check 09-create-ecs-resources.sh"; else echo "   OK: Execution Role found."
    # Check required policies are attached
    echo -n "      Checking for standard ECS Task Execution Policy... "
    aws iam list-attached-role-policies --role-name $ROLE_NAME --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy']" --output text --region $AWS_REGION | grep -q . && echo "OK" || echo "NOT FOUND -> Check 09-create-ecs-resources.sh"
    echo -n "      Checking for SSM Policy ($SSM_POLICY_ARN)... "
    aws iam list-attached-role-policies --role-name $ROLE_NAME --query "AttachedPolicies[?PolicyArn=='$SSM_POLICY_ARN']" --output text --region $AWS_REGION | grep -q . && echo "OK" || echo "NOT FOUND -> Check 09-create-ecs-resources.sh"
fi

# --- Security Group Check ---
# Check the main VPC SG used by the service/endpoints
echo "\n6. Checking Main VPC Security Group Rules ($VPC_SECURITY_GROUP_ID)..."
SG_DETAILS=$(aws ec2 describe-security-groups --group-ids $VPC_SECURITY_GROUP_ID --region $AWS_REGION 2>/dev/null)
if [ $? -ne 0 ]; then echo "   Error: Failed to describe security group '$VPC_SECURITY_GROUP_ID'."; else echo "   OK: Security group found."
    EGRESS_RULES=$(echo "$SG_DETAILS" | jq '.SecurityGroups[0].IpPermissionsEgress')
    echo "      Egress Rules (Outbound):"
    echo $EGRESS_RULES | jq .
    # Check if allows all outbound TCP to VPC endpoints (HTTPS)
    ALLOWS_HTTPS_EGRESS=$(echo "$EGRESS_RULES" | jq 'map(select(.IpProtocol == "tcp" and .ToPort == 443 and (.IpRanges[]?.CidrIp == "0.0.0.0/0" or .PrefixListIds | length > 0))) | length > 0')
    # Also check for All Traffic Egress
    ALLOWS_ALL_EGRESS=$(echo "$EGRESS_RULES" | jq 'map(select(.IpProtocol == "-1" and .IpRanges[]?.CidrIp == "0.0.0.0/0")) | length > 0')
    
    if [ "$ALLOWS_HTTPS_EGRESS" = "true" ] || [ "$ALLOWS_ALL_EGRESS" = "true" ]; then 
        echo "      OK: Appears to allow necessary outbound HTTPS traffic (needed for endpoints)." 
    else 
        echo "      Warning: No rule found explicitly allowing outbound HTTPS (port 443) to 0.0.0.0/0 or AWS Prefix Lists, nor an All Traffic rule. VPC Endpoints might be blocked. -> Check SG rules."
    fi
fi

# --- Recent Task Failures ---
echo "\n7. Checking Recent Task Failures (last 5 stopped tasks)..."
STOPPED_TASKS=$(aws ecs list-tasks --cluster $ECS_CLUSTER_NAME --service-name $ECS_SERVICE_NAME --desired-status STOPPED --max-items 5 --query 'taskArns' --output json --region $AWS_REGION 2>/dev/null)

if [[ -z "$STOPPED_TASKS" || "$STOPPED_TASKS" == "[]" || "$STOPPED_TASKS" == "null" ]]; then 
    echo "   No recently stopped tasks found for service $ECS_SERVICE_NAME."
else 
    echo "   Found recently stopped tasks:"
    # Use text output for easier parsing in scripts if needed, table for user readability
    aws ecs describe-tasks --cluster $ECS_CLUSTER_NAME --tasks $STOPPED_TASKS --query 'tasks[*].{ARN:taskArn, LastStatus:lastStatus, StoppedReason:stoppedReason, StartedAt:startedAt, StoppedAt:stoppedAt, ContainerExitCode:containers[0].exitCode, ContainerReason:containers[0].reason}' --output table --region $AWS_REGION
fi

echo "\nDiagnosis complete."

# --- Summary & Suggestions ---
echo "\n--- Summary & Potential Issues ---"
echo "Review the checks above. Common issues causing ECS tasks (esp. with SSM secrets) to fail on startup include:"
echo "  - Missing/Misconfigured VPC Endpoints (Check 2): Tasks in private subnets can't reach AWS APIs (SSM, ECR, Logs)."
echo "      -> Ensure '03-setup-networking.sh' ran successfully."
echo "  - Incorrect Task Definition (Check 3): Wrong network mode (needs awsvpc), wrong execution role ARN, missing container defs, incorrect secret ARNs."
echo "      -> Check '09-create-ecs-resources.sh' and ensure secrets in '07-create-secrets.sh' use names '${APP_NAME}-...'"
echo "  - Incorrect Service Configuration (Check 4): Wrong subnets (needs private), wrong security groups, public IP enabled (should be disabled)."
echo "      -> Check '09-create-ecs-resources.sh'."
echo "  - Missing IAM Permissions (Check 5): Execution role missing standard policy or the specific SSM policy."
echo "      -> Check '09-create-ecs-resources.sh' where the role and policy attachment occur."
echo "  - Security Group Blocking Egress (Check 6): Outbound rules on the VPC security group don't allow HTTPS traffic to AWS endpoints."
echo "      -> Check the Egress rules on SG '$VPC_SECURITY_GROUP_ID'."
echo "  - Application Error (Check 7): Look at the 'StoppedReason' and 'ContainerReason' for clues. Check CloudWatch Logs for the task."
echo "      -> Check application code and Dockerfile. Check CloudWatch log group '/ecs/${APP_NAME}-task'."
echo "\nAfter fixing issues, you might need to re-run '09-create-ecs-resources.sh' and/or '10-finalize-deployment.sh' to update the service." 
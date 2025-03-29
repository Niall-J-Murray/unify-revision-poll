#!/bin/bash

# WARNING: This script is destructive and will delete AWS resources.
# Use with extreme caution.

# --- Source Configs FIRST --- 
# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source primary variables - needed for names and AWS_ACCOUNT_ID
if [ -f "$SCRIPT_DIR/01-setup-variables.sh" ]; then
    source "$SCRIPT_DIR/01-setup-variables.sh"
else
    echo "Error: 01-setup-variables.sh not found. Cannot determine resource names/account ID."
    exit 1
fi

# Source other configuration files if they exist
[ -f "$SCRIPT_DIR/vpc-config.sh" ] && source "$SCRIPT_DIR/vpc-config.sh"
[ -f "$SCRIPT_DIR/rds-config.sh" ] && source "$SCRIPT_DIR/rds-config.sh"
[ -f "$SCRIPT_DIR/ecr-config.sh" ] && source "$SCRIPT_DIR/ecr-config.sh"
[ -f "$SCRIPT_DIR/certificate-config.sh" ] && source "$SCRIPT_DIR/certificate-config.sh"
[ -f "$SCRIPT_DIR/alb-config.sh" ] && source "$SCRIPT_DIR/alb-config.sh"
[ -f "$SCRIPT_DIR/nat-gateway-config.sh" ] && source "$SCRIPT_DIR/nat-gateway-config.sh"
[ -f "$SCRIPT_DIR/secrets-config.sh" ] && source "$SCRIPT_DIR/secrets-config.sh"
# --- End Sourcing ---

echo "AWS Resource Cleanup Script"
echo "==========================="
echo "WARNING: This will attempt to delete resources associated with the application: $APP_NAME"
echo "It relies on configuration files created by the deployment scripts."
echo ""

# --- Confirmation Prompt ---
echo "Resources potentially targeted for deletion in region $AWS_REGION:"
echo "- ECS Service: ${APP_NAME}-service"
echo "- ECS Cluster: ${APP_NAME}-cluster"
echo "- ECS Task Definitions (family): ${APP_NAME}-task"
echo "- ALB Listeners (HTTP/HTTPS)"
echo "- Target Group: ${APP_NAME}-tg"
echo "- Application Load Balancer: ${APP_NAME}-alb"
echo "- IAM Role: ${APP_NAME}-ecs-execution-role"
echo "- IAM Policy (Custom): feature-poll-CustomECSTaskExecutionPolicy (if created)"
echo "- IAM Policy (SSM): ${APP_NAME}-ssm-parameter-access-policy"
echo "- ACM Certificate: ARN = $CERTIFICATE_ARN"
echo "- RDS DB Instance: ${APP_NAME}-db"
echo "- DB Subnet Group: ${APP_NAME}-db-subnet-group"
echo "- Security Groups: ${APP_NAME}-db-sg, ${APP_NAME}-ecs-sg, ${APP_NAME}-alb-sg"
echo "- ECR Repository: ${APP_NAME}-repo"
echo "- NAT Gateway: ID = $NAT_GATEWAY_ID"
echo "- Elastic IP: AllocationID = $EIP_ALLOCATION_ID"
echo "- Subnets (Public/Private)"
echo "- Route Tables (Public/Private)"
echo "- Internet Gateway"
echo "- VPC: ${APP_NAME}-vpc"
echo "- Config files in $SCRIPT_DIR"
# echo "- SSM Parameters: ${APP_NAME}-*" # Optional - uncomment to delete

echo ""
read -p "ARE YOU ABSOLUTELY SURE you want to delete these resources? (yes/no): " CONFIRMATION
if [ "$CONFIRMATION" != "yes" ]; then
    echo "Cleanup aborted."
    exit 0
fi

echo "Proceeding with cleanup..."

# --- Deletion Steps (Reverse Order) ---

# 1. ECS Service - Set desired count to 0 and delete
echo "Deleting ECS Service: ${APP_NAME}-service..."
if aws ecs describe-services --cluster "${APP_NAME}-cluster" --services "${APP_NAME}-service" --query 'services[?status!=`INACTIVE`]' --output text --region $AWS_REGION | grep -q .; then
    echo "Setting desired count to 0..."
    aws ecs update-service --cluster "${APP_NAME}-cluster" --service "${APP_NAME}-service" --desired-count 0 --region $AWS_REGION
    echo "Waiting for service tasks to drain (approx 1 min)..."
    sleep 60 # Give time for tasks to stop
    aws ecs delete-service --cluster "${APP_NAME}-cluster" --service "${APP_NAME}-service" --force --region $AWS_REGION || echo "WARN: Failed to delete ECS Service (may not exist or already deleting)."
else
    echo "ECS Service not found or inactive."
fi

# 2. ECS Task Definitions - Deregister all revisions
echo "Deregistering ECS Task Definitions (family: ${APP_NAME}-task)..."
TASK_DEFS=$(aws ecs list-task-definitions --family-prefix "${APP_NAME}-task" --status ACTIVE --query 'taskDefinitionArns[*]' --output text --region $AWS_REGION)
if [ -n "$TASK_DEFS" ]; then
    for task_def_arn in $TASK_DEFS; do
        echo "Deregistering $task_def_arn"
        aws ecs deregister-task-definition --task-definition $task_def_arn --region $AWS_REGION || echo "WARN: Failed to deregister $task_def_arn"
    done
else
    echo "No active task definitions found for family ${APP_NAME}-task."
fi

# 3. ALB Listeners
echo "Deleting ALB Listeners..."
if [ ! -z "$ALB_ARN" ]; then
    LISTENER_ARNS=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query 'Listeners[*].ListenerArn' --output text --region $AWS_REGION)
    if [ -n "$LISTENER_ARNS" ]; then
        for listener_arn in $LISTENER_ARNS; do
            echo "Deleting Listener $listener_arn"
            aws elbv2 delete-listener --listener-arn $listener_arn --region $AWS_REGION || echo "WARN: Failed to delete Listener $listener_arn"
        done
    else
        echo "No listeners found for ALB $ALB_ARN."
    fi
else
    echo "Skipping listener deletion: ALB ARN not found in config."
fi

# 4. Target Group
echo "Deleting Target Group: ${APP_NAME}-tg..."
if [ ! -z "$TARGET_GROUP_ARN" ]; then # Assuming TARGET_GROUP_ARN is saved somewhere - need to add this to script 09!
    # Let's query by name instead for robustness
    TG_ARN_QUERY=$(aws elbv2 describe-target-groups --names "${APP_NAME}-tg" --query 'TargetGroups[0].TargetGroupArn' --output text --region $AWS_REGION 2>/dev/null)
    if [ ! -z "$TG_ARN_QUERY" ] && [ "$TG_ARN_QUERY" != "None" ]; then
        aws elbv2 delete-target-group --target-group-arn $TG_ARN_QUERY --region $AWS_REGION || echo "WARN: Failed to delete Target Group ${APP_NAME}-tg"
    else
        echo "Target Group ${APP_NAME}-tg not found."
    fi
else
     echo "WARN: Target Group ARN not found in config (Script 09 needs to save it)."
fi


# 5. Application Load Balancer
echo "Deleting Application Load Balancer: ${APP_NAME}-alb..."
if [ ! -z "$ALB_ARN" ]; then
    aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN --region $AWS_REGION || echo "WARN: Failed to delete ALB $ALB_ARN (allow ~1 min for listeners/TGs to detach)."
    echo "Waiting for ALB deletion (approx 1 min)..."
    sleep 60
else
    echo "Skipping ALB deletion: ALB ARN not found in config."
fi

# 6. ACM Certificate
echo "Deleting ACM Certificate: $CERTIFICATE_ARN..."
if [ ! -z "$CERTIFICATE_ARN" ]; then
    aws acm delete-certificate --certificate-arn $CERTIFICATE_ARN --region $AWS_REGION || echo "WARN: Failed to delete ACM Certificate $CERTIFICATE_ARN (may already be deleted or in use)."
else
    echo "Skipping Certificate deletion: ARN not found in config."
fi

# 7. Detach & Delete IAM Policies and Role
CUSTOM_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/feature-poll-CustomECSTaskExecutionPolicy"
SSM_POLICY_NAME="${APP_NAME}-ssm-parameter-access-policy"
ROLE_NAME="${APP_NAME}-ecs-execution-role"
INSTANCE_PROFILE_NAME=$ROLE_NAME # Usually same name

if [ -z "$SSM_POLICY_ARN" ]; then
    echo "SSM Policy ARN not loaded from config, trying to find by name..."
    SSM_POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='$SSM_POLICY_NAME'].Arn" --output text --region $AWS_REGION 2>/dev/null)
fi

echo "Detaching/Deleting IAM Role, Instance Profile, and Policies for $ROLE_NAME..."
if aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text --region $AWS_REGION > /dev/null 2>&1; then
    # Detach known policies
    echo "Detaching Custom Policy ($CUSTOM_POLICY_ARN)..."
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $CUSTOM_POLICY_ARN --region $AWS_REGION || echo "WARN: Failed to detach Custom Policy (may not be attached or ARN incorrect)."
    echo "Detaching Standard ECS Policy (arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy)..."
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy --region $AWS_REGION || echo "WARN: Failed to detach Standard Policy (may not be attached)."
    if [ ! -z "$SSM_POLICY_ARN" ] && [ "$SSM_POLICY_ARN" != "None" ]; then
         echo "Detaching SSM Policy ($SSM_POLICY_ARN)..."
         aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $SSM_POLICY_ARN --region $AWS_REGION || echo "WARN: Failed to detach SSM Policy (may not be attached)."
    else
        echo "WARN: SSM Policy ARN not found, cannot detach from role $ROLE_NAME by ARN."
    fi

    # --- NEW: Remove role from instance profile --- 
    echo "Removing role $ROLE_NAME from instance profile $INSTANCE_PROFILE_NAME..."
    aws iam remove-role-from-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --role-name $ROLE_NAME --region $AWS_REGION || echo "WARN: Failed to remove role from instance profile (may not exist or role not added)."

    # Sometimes detachment takes a moment
    echo "Waiting briefly for detachments..."
    sleep 10 # Increased wait time

    echo "Deleting IAM Role $ROLE_NAME..."
    aws iam delete-role --role-name $ROLE_NAME --region $AWS_REGION || echo "WARN: Failed to delete IAM Role $ROLE_NAME (Check if policies/instance profile are truly detached)."

    # --- NEW: Delete instance profile --- 
    echo "Deleting instance profile $INSTANCE_PROFILE_NAME..."
    aws iam delete-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --region $AWS_REGION || echo "WARN: Failed to delete instance profile (may not exist)."

else
    echo "IAM Role $ROLE_NAME not found."
    # Try deleting instance profile anyway in case it was orphaned
    echo "Deleting instance profile $INSTANCE_PROFILE_NAME (attempting even if role not found)..."
    aws iam delete-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --region $AWS_REGION || echo "WARN: Failed to delete instance profile (may not exist)."
fi

# Delete policies after role (if possible)
echo "Deleting Custom Policy ($CUSTOM_POLICY_ARN)..."
# --- FIX: Use the variable containing the account ID --- 
aws iam delete-policy --policy-arn "$CUSTOM_POLICY_ARN" --region $AWS_REGION || echo "WARN: Failed to delete Custom Policy (may not exist or ARN incorrect)."

if [ ! -z "$SSM_POLICY_ARN" ] && [ "$SSM_POLICY_ARN" != "None" ]; then
    echo "Deleting SSM Policy ($SSM_POLICY_ARN)..."
    aws iam delete-policy --policy-arn "$SSM_POLICY_ARN" --region $AWS_REGION || echo "WARN: Failed to delete SSM Policy (may not exist or already deleted)."
else
     echo "WARN: SSM Policy ARN not found, cannot delete by ARN."
fi

# 8. RDS Instance
echo "Deleting RDS Instance: ${APP_NAME}-db..."
if aws rds describe-db-instances --db-instance-identifier "${APP_NAME}-db" --query 'DBInstances[0].DBInstanceIdentifier' --output text --region $AWS_REGION > /dev/null 2>&1; then
    aws rds delete-db-instance --db-instance-identifier "${APP_NAME}-db" --skip-final-snapshot --delete-automated-backups --region $AWS_REGION || echo "WARN: Failed to initiate RDS deletion for ${APP_NAME}-db."
    echo "Waiting for RDS deletion (can take several minutes)..."
    aws rds wait db-instance-deleted --db-instance-identifier "${APP_NAME}-db" --region $AWS_REGION || echo "WARN: Wait for RDS deletion failed or timed out."
else
    echo "RDS Instance ${APP_NAME}-db not found."
fi

# 9. DB Subnet Group
DB_SUBNET_GROUP_NAME_TO_DELETE="${APP_NAME}-subnet-group"
echo "Deleting DB Subnet Group: $DB_SUBNET_GROUP_NAME_TO_DELETE..."
# --- FIX: Check variable first --- 
if [ -z "$DB_SUBNET_GROUP_NAME_TO_DELETE" ]; then
    echo "Skipping DB Subnet Group deletion: Name is empty."
elif aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP_NAME_TO_DELETE" --query 'DBSubnetGroups[0].DBSubnetGroupName' --output text --region $AWS_REGION > /dev/null 2>&1; then
    aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP_NAME_TO_DELETE" --region $AWS_REGION || echo "WARN: Failed to delete DB Subnet Group $DB_SUBNET_GROUP_NAME_TO_DELETE."
else
    echo "DB Subnet Group $DB_SUBNET_GROUP_NAME_TO_DELETE not found."
fi

# 10. Remove SG Rules (Dependencies must be removed before deleting SGs)
# Need the SG IDs - assuming they are in vpc-config.sh and rds-config.sh
DB_SG_ID=$SECURITY_GROUP_ID # From rds-config.sh
ALB_SG_NAME="${APP_NAME}-alb-sg"
ECS_SG_NAME="${APP_NAME}-ecs-sg"
DB_SG_NAME="${APP_NAME}-db-sg" # Assuming this was the name used

ALB_SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=$ALB_SG_NAME Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
ECS_SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=$ECS_SG_NAME Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
# DB_SG_ID is already sourced if rds-config exists

echo "Revoking Security Group Rules..."
if [ ! -z "$DB_SG_ID" ] && [ ! -z "$ECS_SG_ID" ]; then
    echo "Revoking DB SG rule allowing access from ECS SG..."
    aws ec2 revoke-security-group-ingress --group-id $DB_SG_ID --protocol tcp --port 5432 --source-group $ECS_SG_ID --region $AWS_REGION || echo "WARN: Failed to revoke DB <- ECS rule."
else
    echo "Skipping DB <- ECS rule revocation (DB_SG_ID or ECS_SG_ID empty)."
fi
if [ ! -z "$ECS_SG_ID" ] && [ ! -z "$ALB_SG_ID" ]; then
     echo "Revoking ECS SG rule allowing access from ALB SG..."
     aws ec2 revoke-security-group-ingress --group-id $ECS_SG_ID --protocol tcp --port $ECS_CONTAINER_PORT --source-group $ALB_SG_ID --region $AWS_REGION || echo "WARN: Failed to revoke ECS <- ALB rule."
else
    echo "Skipping ECS <- ALB rule revocation (ECS_SG_ID or ALB_SG_ID empty)."
fi
# Note: Ingress rules from 0.0.0.0/0 on ALB SG are usually fine to leave until SG deletion

# 11. Delete Security Groups
echo "Deleting Security Groups..."
# --- FIX: Add checks for empty IDs --- 
if [ ! -z "$ECS_SG_ID" ]; then
    aws ec2 delete-security-group --group-id $ECS_SG_ID --region $AWS_REGION || echo "WARN: Failed to delete ECS SG $ECS_SG_ID."
else
    echo "Skipping ECS SG deletion (ID empty)."
fi
if [ ! -z "$ALB_SG_ID" ]; then
    aws ec2 delete-security-group --group-id $ALB_SG_ID --region $AWS_REGION || echo "WARN: Failed to delete ALB SG $ALB_SG_ID."
else
    echo "Skipping ALB SG deletion (ID empty)."
fi
if [ ! -z "$DB_SG_ID" ]; then
     aws ec2 delete-security-group --group-id $DB_SG_ID --region $AWS_REGION || echo "WARN: Failed to delete DB SG $DB_SG_ID."
else
    echo "Skipping DB SG deletion (ID empty)."
fi

# 12. ECR Repository
echo "Deleting ECR Repository: ${APP_NAME}-repo..."
if aws ecr describe-repositories --repository-names "${APP_NAME}-repo" --region $AWS_REGION > /dev/null 2>&1; then
    aws ecr delete-repository --repository-name "${APP_NAME}-repo" --force --region $AWS_REGION || echo "WARN: Failed to delete ECR repo ${APP_NAME}-repo."
else
    echo "ECR Repo ${APP_NAME}-repo not found."
fi

# 13. NAT Gateway
echo "Deleting NAT Gateway..."
# Try ID from config first
NAT_GW_TO_DELETE=$NAT_GATEWAY_ID 
# If empty, try finding by tag
if [ -z "$NAT_GW_TO_DELETE" ]; then
    echo "NAT Gateway ID not loaded from config, trying to find by tag AppName=$APP_NAME..."
    NAT_GW_TO_DELETE=$(aws ec2 describe-nat-gateways --filter "Name=tag:AppName,Values=$APP_NAME" "Name=state,Values=pending,available" --query 'NatGateways[0].NatGatewayId' --output text --region $AWS_REGION 2>/dev/null)
fi

if [ ! -z "$NAT_GW_TO_DELETE" ] && [ "$NAT_GW_TO_DELETE" != "None" ]; then
     echo "Found NAT Gateway to delete: $NAT_GW_TO_DELETE"
     aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW_TO_DELETE --region $AWS_REGION || echo "WARN: Failed to delete NAT Gateway $NAT_GW_TO_DELETE."
     echo "Waiting for NAT Gateway deletion (approx 1-2 min)..."
     aws ec2 wait nat-gateway-deleted --nat-gateway-id $NAT_GW_TO_DELETE --region $AWS_REGION || echo "WARN: Wait for NAT Gateway deletion failed or timed out."
else
    echo "No active NAT Gateway found to delete (either by config ID or AppName tag)."
fi

# 14. Release Elastic IP
echo "Releasing Elastic IP..."
# Try ID from config first
EIP_ALLOC_TO_RELEASE=$EIP_ALLOCATION_ID
# If empty, try finding EIP associated with the (now deleted/deleting) NAT GW - THIS IS HARD
# Alternative: Find EIPs tagged for the app? (Requires tagging EIP in script 03)
# Let's just rely on the config for now.
if [ ! -z "$EIP_ALLOC_TO_RELEASE" ]; then
    echo "Attempting to release Elastic IP with AllocationID: $EIP_ALLOC_TO_RELEASE..."
    aws ec2 release-address --allocation-id $EIP_ALLOC_TO_RELEASE --region $AWS_REGION || echo "WARN: Failed to release Elastic IP $EIP_ALLOC_TO_RELEASE (may already be released or ID invalid)."
else
    echo "Skipping Elastic IP release: Allocation ID not found in config."
fi

# 15. Delete Subnets
echo "Deleting Subnets..."
# --- FIX: Add checks for empty IDs --- 
if [ ! -z "$PUBLIC_SUBNET_1_ID" ]; then
    aws ec2 delete-subnet --subnet-id $PUBLIC_SUBNET_1_ID --region $AWS_REGION || echo "WARN: Failed to delete Public Subnet 1 $PUBLIC_SUBNET_1_ID."
else echo "Skipping Public Subnet 1 deletion (ID empty)."; fi
if [ ! -z "$PUBLIC_SUBNET_2_ID" ]; then
    aws ec2 delete-subnet --subnet-id $PUBLIC_SUBNET_2_ID --region $AWS_REGION || echo "WARN: Failed to delete Public Subnet 2 $PUBLIC_SUBNET_2_ID."
else echo "Skipping Public Subnet 2 deletion (ID empty)."; fi
if [ ! -z "$PRIVATE_SUBNET_1_ID" ]; then
    aws ec2 delete-subnet --subnet-id $PRIVATE_SUBNET_1_ID --region $AWS_REGION || echo "WARN: Failed to delete Private Subnet 1 $PRIVATE_SUBNET_1_ID."
else echo "Skipping Private Subnet 1 deletion (ID empty)."; fi
if [ ! -z "$PRIVATE_SUBNET_2_ID" ]; then
    aws ec2 delete-subnet --subnet-id $PRIVATE_SUBNET_2_ID --region $AWS_REGION || echo "WARN: Failed to delete Private Subnet 2 $PRIVATE_SUBNET_2_ID."
else echo "Skipping Private Subnet 2 deletion (ID empty)."; fi

# 16. Delete Route Tables (Try deleting custom ones, default cannot be deleted)
PUBLIC_ROUTE_TABLE_NAME="${APP_NAME}-public-rtb"
PRIVATE_ROUTE_TABLE_NAME="${APP_NAME}-private-rtb"
# Try ID from config first
PUB_RTB_TO_DELETE=$PUBLIC_ROUTE_TABLE_ID
PRIV_RTB_TO_DELETE=$PRIVATE_ROUTE_TABLE_ID

# If empty, try finding by tag
if [ -z "$PUB_RTB_TO_DELETE" ]; then
   PUB_RTB_TO_DELETE=$(aws ec2 describe-route-tables --filters Name=tag:Name,Values=$PUBLIC_ROUTE_TABLE_NAME Name=vpc-id,Values=$VPC_ID --query 'RouteTables[?length(Associations[?Main!=`true`]) > `0` || length(Associations)==`0`].RouteTableId' --output text --region $AWS_REGION 2>/dev/null)
fi
if [ -z "$PRIV_RTB_TO_DELETE" ]; then
   PRIV_RTB_TO_DELETE=$(aws ec2 describe-route-tables --filters Name=tag:Name,Values=$PRIVATE_ROUTE_TABLE_NAME Name=vpc-id,Values=$VPC_ID --query 'RouteTables[?length(Associations[?Main!=`true`]) > `0` || length(Associations)==`0`].RouteTableId' --output text --region $AWS_REGION 2>/dev/null)
fi

echo "Deleting Custom Route Tables..."
if [ ! -z "$PUB_RTB_TO_DELETE" ] && [ "$PUB_RTB_TO_DELETE" != "None" ]; then
    echo "Deleting Public Route Table $PUB_RTB_TO_DELETE"
    aws ec2 delete-route-table --route-table-id $PUB_RTB_TO_DELETE --region $AWS_REGION || echo "WARN: Failed to delete Public Route Table $PUB_RTB_TO_DELETE."
else
    echo "Public Route Table not found by config or tag."
fi
if [ ! -z "$PRIV_RTB_TO_DELETE" ] && [ "$PRIV_RTB_TO_DELETE" != "None" ]; then
    echo "Deleting Private Route Table $PRIV_RTB_TO_DELETE"
    aws ec2 delete-route-table --route-table-id $PRIV_RTB_TO_DELETE --region $AWS_REGION || echo "WARN: Failed to delete Private Route Table $PRIV_RTB_TO_DELETE."
else
     echo "Private Route Table not found by config or tag."
fi

# 17. Detach and Delete Internet Gateway
echo "Detaching/Deleting Internet Gateway..."
# --- FIX: Check VPC_ID --- 
if [ -z "$VPC_ID" ]; then
    echo "Skipping IGW deletion (VPC_ID empty)."
else
    IGW_ID=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC_ID --query 'InternetGateways[0].InternetGatewayId' --output text --region $AWS_REGION 2>/dev/null)
    if [ ! -z "$IGW_ID" ] && [ "$IGW_ID" != "None" ]; then
        aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION || echo "WARN: Failed to detach Internet Gateway $IGW_ID."
        aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $AWS_REGION || echo "WARN: Failed to delete Internet Gateway $IGW_ID."
    else
        echo "Internet Gateway not found for VPC $VPC_ID."
    fi
fi

# 18. Delete VPC
echo "Deleting VPC: ${APP_NAME}-vpc (ID: $VPC_ID)..."
# --- FIX: Check VPC_ID --- 
if [ ! -z "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    aws ec2 delete-vpc --vpc-id $VPC_ID --region $AWS_REGION || echo "WARN: Failed to delete VPC $VPC_ID (ensure all dependencies like subnets, RTBs, IGW, SGs are deleted)."
else
    echo "Skipping VPC deletion: ID not found in config or empty."
fi

# 19. Delete ECS Cluster
echo "Deleting ECS Cluster: ${APP_NAME}-cluster..."
if aws ecs describe-clusters --clusters "${APP_NAME}-cluster" --query 'clusters[?status!=`INACTIVE`]' --output text --region $AWS_REGION | grep -q .; then
    aws ecs delete-cluster --cluster "${APP_NAME}-cluster" --region $AWS_REGION || echo "WARN: Failed to delete ECS Cluster ${APP_NAME}-cluster (ensure service is deleted)."
else
    echo "ECS Cluster ${APP_NAME}-cluster not found or inactive."
fi

# 20. Optional: Delete SSM Parameters
# echo "Deleting SSM Parameters (prefix: ${APP_NAME}-*)..."
# PARAM_NAMES=$(aws ssm get-parameters-by-path --path "/${APP_NAME}" --recursive --query 'Parameters[*].Name' --output text --region $AWS_REGION) # Note: SSM path uses /
# If using hyphenated names, this path approach might not work easily. Need list-parameters + filter or delete individually.
# echo "SSM Parameter deletion commented out for safety."

# 21. Delete local config files
echo "Deleting local configuration files..."
rm -f "$SCRIPT_DIR/vpc-config.sh"
rm -f "$SCRIPT_DIR/rds-config.sh"
rm -f "$SCRIPT_DIR/ecr-config.sh"
rm -f "$SCRIPT_DIR/certificate-config.sh"
rm -f "$SCRIPT_DIR/alb-config.sh"
rm -f "$SCRIPT_DIR/nat-gateway-config.sh"
rm -f "$SCRIPT_DIR/secrets-config.sh"
echo "Local config files removed."


echo "Cleanup script finished." 
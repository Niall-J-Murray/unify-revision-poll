#!/bin/bash

# WARNING: This script is destructive and will delete AWS resources.
# Use with extreme caution.

# --- Source Configs FIRST --- 
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"

if [ -f "$SCRIPT_DIR/01-setup-variables.sh" ]; then source "$SCRIPT_DIR/01-setup-variables.sh"; else echo "Error: 01-setup-variables.sh not found."; exit 1; fi
# Source other config files safely from config/
config_files=("vpc-config.sh" "rds-config.sh" "ecr-config.sh" "certificate-config.sh" "alb-config.sh" "nat-gateway-config.sh" "secrets-config.sh" "bastion-config.sh" "ecs-config.sh")
for cfg in "${config_files[@]}"; do
    [ -f "$CONFIG_DIR/$cfg" ] && source "$CONFIG_DIR/$cfg"
done
# --- End Sourcing ---

# --- Attempt to get Account ID if not in vars ---
# Set default region if not set
AWS_REGION=${AWS_REGION:-"eu-west-1"} 
if [ -z "$AWS_ACCOUNT_ID" ]; then AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region $AWS_REGION 2>/dev/null); fi
if [ -z "$AWS_ACCOUNT_ID" ]; then echo "Error: Could not determine AWS Account ID. Please configure AWS CLI or set AWS_ACCOUNT_ID environment variable."; exit 1; fi

echo "AWS Resource Cleanup Script for '$APP_NAME' in region '$AWS_REGION' (Account: $AWS_ACCOUNT_ID)"
echo "=================================================================="
echo "WARNING: This will attempt to delete resources associated with the application: $APP_NAME"
echo "It relies on configuration files created by the deployment scripts."

# --- Important Notes on Cleanup --- 
# - Order Matters: Deletion follows reverse creation order. Dependencies must be removed first.
# - Idempotency: The script attempts to check if resources exist before deletion, but failures can occur.
# - Dependencies: AWS prevents deletion of resources with active dependencies (e.g., VPC with running instances/endpoints/NAT GWs). 
#   This script tries to remove known dependencies first, but complex or manually created dependencies might cause errors.
# - Manual Verification: Always check the AWS console after running to ensure all intended resources were deleted and no orphans remain.
# - Errors: If errors occur, note the resource causing the failure, manually investigate/delete it in the AWS console, and potentially re-run the script.
# --- End Notes ---

# --- Dynamically Load ARNs/IDs if missing from config (Best Effort) ---
# Load Execution Role ARN from Task Def if missing
if [ -z "$ECS_EXECUTION_ROLE_ARN" ] && [ -n "$ECS_TASK_FAMILY" ]; then
     ECS_EXECUTION_ROLE_ARN=$(aws ecs describe-task-definition --task-definition $ECS_TASK_FAMILY --query 'taskDefinition.executionRoleArn' --output text --region $AWS_REGION 2>/dev/null)
fi
# Load SSM Policy ARN by name if missing
if [ -z "$SSM_POLICY_ARN" ] && [ -n "$APP_NAME" ]; then
    SSM_POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName==\`${APP_NAME}-ssm-parameter-access-policy\`].Arn" --output text --region $AWS_REGION 2>/dev/null)
fi
# Load ALB ARN by name if missing
if [ -z "$ALB_ARN" ] && [ -n "$ALB_NAME" ]; then
    ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" --query 'LoadBalancers[0].LoadBalancerArn' --output text --region $AWS_REGION 2>/dev/null)
fi
# Load Target Group ARN by name if missing
if [ -z "$TARGET_GROUP_ARN" ] && [ -n "$ALB_TG_NAME" ]; then
    TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --names "$ALB_TG_NAME" --query 'TargetGroups[0].TargetGroupArn' --output text --region $AWS_REGION 2>/dev/null)
fi
# Load VPC ID by tag if missing
if [ -z "$VPC_ID" ] && [ -n "$APP_NAME" ]; then
    VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values="${APP_NAME}-vpc" --query 'Vpcs[0].VpcId' --output text --region $AWS_REGION 2>/dev/null)
fi

# --- List Resources to be Deleted (Informational) ---
echo ""
echo "Potential Resource Deletion Summary (based on config files & dynamic lookup):"
# ECS
[ -n "$ECS_SERVICE_NAME" ] && echo "- ECS Service: $ECS_SERVICE_NAME" 
[ -n "$ECS_CLUSTER_NAME" ] && echo "- ECS Cluster: $ECS_CLUSTER_NAME" 
[ -n "$ECS_TASK_FAMILY" ] && echo "- ECS Task Definitions (family): $ECS_TASK_FAMILY" 
# ALB
[ -n "$ALB_ARN" ] && echo "- ALB: $ALB_ARN" 
[ -n "$TARGET_GROUP_ARN" ] && echo "- Target Group: $TARGET_GROUP_ARN" 
[ -n "$ALB_ARN" ] && echo "- ALB Listeners associated with above ALB"
# IAM
[ -n "$ECS_EXECUTION_ROLE_ARN" ] && echo "- IAM Role: $(basename $ECS_EXECUTION_ROLE_ARN)" 
[ -n "$SSM_POLICY_ARN" ] && echo "- IAM Policy (SSM): $SSM_POLICY_ARN" 
[ -n "$ECS_EXECUTION_ROLE_ARN" ] && echo "- IAM Instance Profile: $(basename $ECS_EXECUTION_ROLE_ARN)" # Assuming name matches role
# ACM
[ -n "$CERTIFICATE_ARN" ] && echo "- ACM Certificate: $CERTIFICATE_ARN" 
# RDS
[ -n "$DB_INSTANCE_IDENTIFIER" ] && echo "- RDS DB Instance: $DB_INSTANCE_IDENTIFIER" 
[ -n "$DB_SUBNET_GROUP_NAME" ] && echo "- DB Subnet Group: $DB_SUBNET_GROUP_NAME" 
# Security Groups (Get IDs by name using VPC_ID)
ALB_SG_ID_CHK=$(aws ec2 describe-security-groups --filters Name=group-name,Values="${APP_NAME}-alb-sg" Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
ECS_SG_ID_CHK=$(aws ec2 describe-security-groups --filters Name=group-name,Values="${APP_NAME}-ecs-sg" Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
DB_SG_ID_CHK=${SECURITY_GROUP_ID:-$(aws ec2 describe-security-groups --filters Name=group-name,Values="${APP_NAME}-db-sg" Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId\' --output text --region $AWS_REGION 2>/dev/null)}
BASTION_SG_ID_CHK=$(aws ec2 describe-security-groups --filters Name=group-name,Values="${APP_NAME}-bastion-sg" Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
VPC_DEFAULT_SG_ID_CHK=${VPC_SECURITY_GROUP_ID:-$(aws ec2 describe-security-groups --filters Name=group-name,Values="${APP_NAME}-default-sg" Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId\' --output text --region $AWS_REGION 2>/dev/null)}
[ -n "$ALB_SG_ID_CHK" ] && echo "- Security Group (ALB): $ALB_SG_ID_CHK (${APP_NAME}-alb-sg)"
[ -n "$ECS_SG_ID_CHK" ] && echo "- Security Group (ECS): $ECS_SG_ID_CHK (${APP_NAME}-ecs-sg)"
[ -n "$DB_SG_ID_CHK" ] && echo "- Security Group (DB): $DB_SG_ID_CHK (${APP_NAME}-db-sg)"
[ -n "$BASTION_SG_ID_CHK" ] && echo "- Security Group (Bastion): $BASTION_SG_ID_CHK (${APP_NAME}-bastion-sg)"
[ -n "$VPC_DEFAULT_SG_ID_CHK" ] && echo "- Security Group (VPC Default): $VPC_DEFAULT_SG_ID_CHK (${APP_NAME}-default-sg)"
# ECR
[ -n "$ECR_REPOSITORY_NAME" ] && echo "- ECR Repository: $ECR_REPOSITORY_NAME" 
# Bastion Host
[ -n "$BASTION_INSTANCE_ID" ] && echo "- Bastion EC2 Instance: $BASTION_INSTANCE_ID" 
[ -n "$BASTION_EIP_ALLOCATION_ID" ] && echo "- Bastion Elastic IP: AllocationID = $BASTION_EIP_ALLOCATION_ID" 
# Networking
[ -n "$NAT_GATEWAY_ID" ] && echo "- NAT Gateway: $NAT_GATEWAY_ID" 
[ -n "$EIP_ALLOCATION_ID" ] && echo "- NAT Gateway Elastic IP: AllocationID = $EIP_ALLOCATION_ID" 
[ -n "$PUBLIC_SUBNET_1_ID" ] && echo "- Subnets (Public): $PUBLIC_SUBNET_1_ID, $PUBLIC_SUBNET_2_ID"
[ -n "$PRIVATE_SUBNET_1_ID" ] && echo "- Subnets (Private): $PRIVATE_SUBNET_1_ID, $PRIVATE_SUBNET_2_ID"
[ -n "$PUBLIC_RT_ID" ] && echo "- Route Table (Public): $PUBLIC_RT_ID"
[ -n "$PRIVATE_ROUTE_TABLE_ID" ] && echo "- Route Table (Private): $PRIVATE_ROUTE_TABLE_ID"
[ -n "$IGW_ID" ] && echo "- Internet Gateway: $IGW_ID"
[ -n "$VPC_ID" ] && echo "- VPC: $VPC_ID (${APP_NAME}-vpc)" 
echo "- Config files in $SCRIPT_DIR"
# SSM Parameters deletion is optional and commented out by default
# [ -n "$SECRET_PARAMETER_PATH_PREFIX" ] && echo "- SSM Parameters: Path prefix $SECRET_PARAMETER_PATH_PREFIX" 

# --- Confirmation Prompt ---
echo ""
read -p "ARE YOU ABSOLUTELY SURE you want to PERMANENTLY DELETE these resources AND the config files in $CONFIG_DIR? (yes/no): " CONFIRMATION
if [ "$CONFIRMATION" != "yes" ]; then echo "Cleanup aborted."; exit 0; fi
echo "Proceeding with cleanup..."

# --- Helper Function for Deletion with Checks ---
# Usage: delete_resource "ResourceType" "Identifier" "aws delete command" ["aws check command" ["check query"]]
delete_resource() {
    local resource_type=$1
    local identifier=$2 
    local delete_cmd=$3
    local check_cmd=$4 # Optional: Command to check existence (e.g., describe)
    local check_query=$5 # Optional: JMESPath query for check command

    if [ -z "$identifier" ] || [[ "$identifier" == "None" ]]; then
        echo "Skipping $resource_type deletion: Identifier missing or 'None'."
        return
    fi

    echo "Attempting to delete $resource_type: $identifier..."
    
    # Check if exists before trying to delete (if check command provided)
    local exists=true
    if [ -n "$check_cmd" ]; then
        # Construct check command with potential identifier argument
        local full_check_cmd="$check_cmd" 
        # Add identifier - requires specific handling based on command structure
        # This part is tricky to generalize; we'll rely on delete failing if not found
        # Example: if [[ $check_cmd == *describe* ]]; then full_check_cmd+=" --some-id $identifier"; fi 
        
        # Simpler check: Execute check and see if it returns non-empty output/success
        if [ -n "$check_query" ]; then
             CHECK_OUTPUT=$($check_cmd --query "$check_query" --output text --region $AWS_REGION 2>/dev/null)
             if ! echo "$CHECK_OUTPUT" | grep -q .; then exists=false; fi # Check if output is non-empty
        elif ! $check_cmd > /dev/null 2>&1; then # Check based on exit code if no query
             exists=false
        fi

        if [ "$exists" = false ]; then
             echo "$resource_type $identifier does not exist or already deleted."
             return
        fi
    fi

    # Execute deletion command
    eval $delete_cmd # Use eval carefully if delete_cmd contains complex structures
    local exit_code=$?
    
    # Provide feedback based on exit code
    if [ $exit_code -ne 0 ]; then
        echo "WARN: Command '$delete_cmd' failed (Exit Code: $exit_code). $resource_type $identifier might be in use, already deleting, or requires dependencies removed first."
    else
        echo "Successfully initiated/completed deletion for $resource_type $identifier."
    fi
    # Return the exit code for potential chaining/error handling
    return $exit_code
}


# --- Deletion Steps (Reverse Order of Creation) ---

# 1. ECS Service (Scale down first)
echo "\n--- Step 1: ECS Service ---"
if [ -n "$ECS_CLUSTER_NAME" ] && [ -n "$ECS_SERVICE_NAME" ]; then
    SERVICE_CHECK_CMD="aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION"
    SERVICE_CHECK_QUERY='services[?status!=`INACTIVE`]'
    if $SERVICE_CHECK_CMD --query "$SERVICE_CHECK_QUERY" --output text 2>/dev/null | grep -q .; then
        echo "Setting desired count to 0 for $ECS_SERVICE_NAME..."
        aws ecs update-service --cluster $ECS_CLUSTER_NAME --service $ECS_SERVICE_NAME --desired-count 0 --region $AWS_REGION
        echo "Waiting for service tasks to drain (approx 1 min)..."
        sleep 60 # Give time for tasks to stop
        delete_resource "ECS Service" $ECS_SERVICE_NAME "aws ecs delete-service --cluster $ECS_CLUSTER_NAME --service $ECS_SERVICE_NAME --force --region $AWS_REGION"
    else
        echo "ECS Service $ECS_SERVICE_NAME not found or inactive."
    fi
else
    echo "Skipping ECS Service deletion: Cluster or Service name missing."
fi

# --- ADDITION: Delete ECS Cluster ---
echo "\n--- Step 1b: ECS Cluster ---"
if [ -n "$ECS_CLUSTER_NAME" ]; then
    # Check if service deletion might still be in progress (wait a bit more)
    sleep 15 
    delete_resource "ECS Cluster" $ECS_CLUSTER_NAME \
        "aws ecs delete-cluster --cluster $ECS_CLUSTER_NAME --region $AWS_REGION" \
        "aws ecs describe-clusters --clusters $ECS_CLUSTER_NAME --region $AWS_REGION" \
        'clusters[?status!=`INACTIVE`]' # Check if not already deleting/deleted
else
    echo "Skipping ECS Cluster deletion: Cluster name missing."
fi

# --- ADDITION: Delete CloudWatch Log Group ---
echo "\n--- Step 1c: CloudWatch Log Group ---"
LOG_GROUP_NAME="/ecs/${APP_NAME}" # Construct the expected log group name
if [ -n "$LOG_GROUP_NAME" ]; then
    delete_resource "CloudWatch Log Group" $LOG_GROUP_NAME \
        "aws logs delete-log-group --log-group-name $LOG_GROUP_NAME --region $AWS_REGION" \
        "aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP_NAME --region $AWS_REGION" \
        "logGroups[?logGroupName==\`$LOG_GROUP_NAME\`]" # Check specific name
else
    echo "Skipping CloudWatch Log Group deletion: Cannot determine name (APP_NAME missing?)."
fi

# 2. ECS Task Definitions (Deregister all revisions)
echo "\n--- Step 2: ECS Task Definitions ---"
if [ -n "$ECS_TASK_FAMILY" ]; then
    echo "Deregistering ECS Task Definitions (family: $ECS_TASK_FAMILY)..."
    TASK_DEFS=$(aws ecs list-task-definitions --family-prefix "$ECS_TASK_FAMILY" --status ACTIVE --query 'taskDefinitionArns[*]' --output text --region $AWS_REGION 2>/dev/null)
    if [ -n "$TASK_DEFS" ]; then
        for task_def_arn in $TASK_DEFS; do
            # No easy check command, just attempt delete
            delete_resource "Task Definition" $task_def_arn "aws ecs deregister-task-definition --task-definition $task_def_arn --region $AWS_REGION"
        done
    else
        echo "No active task definitions found for family $ECS_TASK_FAMILY."
    fi
else
    echo "Skipping Task Definition deregistration: Family name missing."
fi

# 3. ALB Listeners
echo "\n--- Step 3: ALB Listeners ---"
if [ -n "$ALB_ARN" ]; then
    LISTENER_ARNS=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --query 'Listeners[*].ListenerArn' --output text --region $AWS_REGION 2>/dev/null)
    if [ -n "$LISTENER_ARNS" ]; then
        for listener_arn in $LISTENER_ARNS; do
             delete_resource "ALB Listener" $listener_arn "aws elbv2 delete-listener --listener-arn $listener_arn --region $AWS_REGION"
        done
    else
        echo "No listeners found for ALB $ALB_ARN."
    fi
else
    echo "Skipping listener deletion: ALB ARN not found."
fi

# 4. Target Group
echo "\n--- Step 4: Target Group ---"
# Use ARN if available, otherwise try name
TG_IDENTIFIER=${TARGET_GROUP_ARN:-$ALB_TG_NAME}
TG_CHECK_PARAM=${TARGET_GROUP_ARN:+--target-group-arns $TARGET_GROUP_ARN} 
TG_CHECK_PARAM=${TG_CHECK_PARAM:-${ALB_TG_NAME:+--names $ALB_TG_NAME}}
DELETE_PARAM=${TARGET_GROUP_ARN:+--target-group-arn $TARGET_GROUP_ARN} # Delete requires ARN

if [ -n "$DELETE_PARAM" ]; then
    delete_resource "Target Group" $TG_IDENTIFIER "aws elbv2 delete-target-group $DELETE_PARAM --region $AWS_REGION" "aws elbv2 describe-target-groups $TG_CHECK_PARAM --region $AWS_REGION" 'TargetGroups[0]' 
elif [ -n "$ALB_TG_NAME" ]; then
     echo "WARN: Target Group ARN missing, attempting to find by name ($ALB_TG_NAME) to delete..."
     TG_ARN_FOUND=$(aws elbv2 describe-target-groups --names "$ALB_TG_NAME" --query 'TargetGroups[0].TargetGroupArn' --output text --region $AWS_REGION 2>/dev/null)
     if [ -n "$TG_ARN_FOUND" ] && [ "$TG_ARN_FOUND" != "None" ]; then
         delete_resource "Target Group" $TG_ARN_FOUND "aws elbv2 delete-target-group --target-group-arn $TG_ARN_FOUND --region $AWS_REGION"
     else
         echo "Could not find Target Group by name $ALB_TG_NAME to delete."
     fi
else
    echo "Skipping Target Group deletion: ARN and Name missing."
fi


# 5. Application Load Balancer
echo "\n--- Step 5: Application Load Balancer ---"
if [ -n "$ALB_ARN" ]; then
    delete_resource "ALB" $ALB_ARN "aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN --region $AWS_REGION" "aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --region $AWS_REGION" 'LoadBalancers[0]'
    if [ $? -eq 0 ]; then # Only wait if delete command likely succeeded
        echo "Waiting longer for ALB deletion and ENI cleanup (approx 90s)..."
        sleep 90
    fi
fi

# 6. ACM Certificate
echo "\n--- Step 6: ACM Certificate ---"
if [ -n "$CERTIFICATE_ARN" ]; then
    delete_resource "ACM Certificate" $CERTIFICATE_ARN "aws acm delete-certificate --certificate-arn $CERTIFICATE_ARN --region $AWS_REGION" "aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region $AWS_REGION" 'Certificate'
fi

# 7. Detach & Delete IAM Policies and Role
echo "\n--- Step 7: IAM Role, Policies, Instance Profile ---"
ROLE_NAME=$(basename "$ECS_EXECUTION_ROLE_ARN")
INSTANCE_PROFILE_NAME=$ROLE_NAME # Assuming name matches
STANDARD_ECS_POLICY="arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

if [ -n "$ROLE_NAME" ] && [ "$ROLE_NAME" != "None" ] ; then
    if aws iam get-role --role-name $ROLE_NAME --region $AWS_REGION > /dev/null 2>&1; then
        echo "Detaching policies from role $ROLE_NAME..."
        aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $STANDARD_ECS_POLICY --region $AWS_REGION || echo "WARN: Failed to detach Standard ECS Policy."
        if [ -n "$SSM_POLICY_ARN" ] && [ "$SSM_POLICY_ARN" != "None" ]; then
            aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $SSM_POLICY_ARN --region $AWS_REGION || echo "WARN: Failed to detach SSM Policy $SSM_POLICY_ARN."
        fi
        # Detach any other custom policies if known (e.g., from old script versions)
        OLD_CUSTOM_POLICY="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/feature-poll-CustomECSTaskExecutionPolicy"
        aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $OLD_CUSTOM_POLICY --region $AWS_REGION 2>/dev/null || true 
        
        echo "Removing role $ROLE_NAME from instance profile $INSTANCE_PROFILE_NAME..."
        aws iam remove-role-from-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --role-name $ROLE_NAME --region $AWS_REGION || echo "WARN: Failed to remove role from instance profile."

        echo "Waiting briefly for detachments..."
        sleep 15 # Increase wait slightly

        # Delete Role - Check command included in helper now
        delete_resource "IAM Role" $ROLE_NAME "aws iam delete-role --role-name $ROLE_NAME --region $AWS_REGION" "aws iam get-role --role-name $ROLE_NAME --region $AWS_REGION"

        # Delete Instance Profile
        delete_resource "IAM Instance Profile" $INSTANCE_PROFILE_NAME "aws iam delete-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --region $AWS_REGION" "aws iam get-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --region $AWS_REGION"

    else
        echo "IAM Role $ROLE_NAME not found."
        # Try deleting instance profile anyway
        delete_resource "IAM Instance Profile" $INSTANCE_PROFILE_NAME "aws iam delete-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --region $AWS_REGION" "aws iam get-instance-profile --instance-profile-name $INSTANCE_PROFILE_NAME --region $AWS_REGION"
    fi
    # Delete policies after detaching from role
    if [ -n "$SSM_POLICY_ARN" ] && [ "$SSM_POLICY_ARN" != "None" ]; then
        # Delete non-default policy versions first
        echo "Deleting non-default versions for policy $SSM_POLICY_ARN..."
        NON_DEFAULT_VERSIONS=$(aws iam list-policy-versions --policy-arn $SSM_POLICY_ARN --query "Versions[?IsDefaultVersion==\`false\`].VersionId" --output text --region $AWS_REGION)
        if [ -n "$NON_DEFAULT_VERSIONS" ]; then
            for version_id in $NON_DEFAULT_VERSIONS; do
                echo "  Deleting version $version_id..."
                aws iam delete-policy-version --policy-arn $SSM_POLICY_ARN --version-id $version_id --region $AWS_REGION || echo "  WARN: Failed to delete version $version_id"
            done
        else
            echo "  No non-default versions found."
        fi
        sleep 5 # Brief wait after version deletion
        # Now delete the policy itself
        delete_resource "SSM IAM Policy" $SSM_POLICY_ARN "aws iam delete-policy --policy-arn $SSM_POLICY_ARN --region $AWS_REGION" "aws iam get-policy --policy-arn $SSM_POLICY_ARN --region $AWS_REGION"
    fi
    # Delete old custom policy if it exists
    delete_resource "Old Custom IAM Policy" $OLD_CUSTOM_POLICY "aws iam delete-policy --policy-arn $OLD_CUSTOM_POLICY --region $AWS_REGION" "aws iam get-policy --policy-arn $OLD_CUSTOM_POLICY --region $AWS_REGION" 2>/dev/null 

else
    echo "Skipping IAM Role/Policy deletion: Role ARN/Name missing or 'None'."
fi


# 8. RDS Instance
echo "\n--- Step 8: RDS Instance ---"
if [ -n "$DB_INSTANCE_IDENTIFIER" ]; then
    DB_CHECK_CMD="aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_IDENTIFIER --region $AWS_REGION"
    DB_CHECK_QUERY='DBInstances[0]'
    if $DB_CHECK_CMD --query "$DB_CHECK_QUERY" --output text 2>/dev/null | grep -q .; then
        # Need to disable deletion protection first if enabled
        PROTECTION=$(aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_IDENTIFIER --query 'DBInstances[0].DeletionProtection' --output text --region $AWS_REGION)
        if [ "$PROTECTION" == "true" ]; then
            echo "Disabling deletion protection for $DB_INSTANCE_IDENTIFIER..."
            aws rds modify-db-instance --db-instance-identifier $DB_INSTANCE_IDENTIFIER --no-deletion-protection --apply-immediately --region $AWS_REGION
            echo "Waiting after disabling deletion protection..."
            sleep 30
        fi
        
        delete_resource "RDS Instance" $DB_INSTANCE_IDENTIFIER "aws rds delete-db-instance --db-instance-identifier $DB_INSTANCE_IDENTIFIER --skip-final-snapshot --delete-automated-backups --region $AWS_REGION"
        
        # Only wait if delete was attempted successfully
        if [ $? -eq 0 ]; then
             echo "Waiting for RDS deletion (can take several minutes)..."
             aws rds wait db-instance-deleted --db-instance-identifier $DB_INSTANCE_IDENTIFIER --region $AWS_REGION || echo "WARN: Wait for RDS deletion failed or timed out."
             echo "Waiting 90 seconds after RDS deletion confirmation for cleanup..."
             sleep 90
        fi
    else
        echo "RDS Instance $DB_INSTANCE_IDENTIFIER not found."
    fi
else
    echo "Skipping RDS deletion: DB Instance Identifier missing."
fi

# 9. DB Subnet Group
echo "\n--- Step 9: DB Subnet Group ---"
if [ -n "$DB_SUBNET_GROUP_NAME" ]; then
    delete_resource "DB Subnet Group" $DB_SUBNET_GROUP_NAME \
        "aws rds delete-db-subnet-group --db-subnet-group-name $DB_SUBNET_GROUP_NAME --region $AWS_REGION" \
        "aws rds describe-db-subnet-groups --db-subnet-group-name $DB_SUBNET_GROUP_NAME --region $AWS_REGION" \
        'DBSubnetGroups[0]'
fi

# 10. Bastion Host EC2 Instance
echo "\n--- Step 10: Bastion Host ---"
if [ -n "$BASTION_INSTANCE_ID" ]; then
     delete_resource "Bastion EC2 Instance" $BASTION_INSTANCE_ID \
        "aws ec2 terminate-instances --instance-ids $BASTION_INSTANCE_ID --region $AWS_REGION" \
        "aws ec2 describe-instances --instance-ids $BASTION_INSTANCE_ID --filters Name=instance-state-name,Values=pending,running,stopping,stopped --region $AWS_REGION" \
        'Reservations[0]'
     if [ $? -eq 0 ]; then # Only wait if terminate succeeded
         echo "Waiting for Bastion instance termination..."
         aws ec2 wait instance-terminated --instance-ids $BASTION_INSTANCE_ID --region $AWS_REGION || echo "WARN: Wait for Bastion termination failed or timed out."
         echo "Waiting 60 seconds after Bastion termination for cleanup..."
         sleep 60
     fi
fi

# 11. ECR Repository
echo "\n--- Step 11: ECR Repository ---"
if [ -n "$ECR_REPOSITORY_NAME" ]; then
    delete_resource "ECR Repository" $ECR_REPOSITORY_NAME \
        "aws ecr delete-repository --repository-name $ECR_REPOSITORY_NAME --force --region $AWS_REGION" \
        "aws ecr describe-repositories --repository-names $ECR_REPOSITORY_NAME --region $AWS_REGION" \
        'repositories[0]'
fi

# --- ADDITION: Attempt to delete lingering ENIs --- 
echo "\n--- Step 11b: Attempting to find and delete lingering Network Interfaces in VPC $VPC_ID ---"
if [ -n "$VPC_ID" ]; then
    # Find ENIs associated with the VPC, potentially filtering by status 'available' or description
    # Filtering by description is often more reliable if resources were tagged well
    echo "Searching for available ENIs in VPC $VPC_ID..."
    LINGERING_ENIS=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text --region $AWS_REGION)
    # Alternative/Additional: Filter by description containing APP_NAME (adjust if needed)
    # LINGERING_ENIS_BY_DESC=$(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" "Name=description,Values=*${APP_NAME}*" "Name=status,Values=available" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text --region $AWS_REGION)
    # Combine results if needed

    if [ -n "$LINGERING_ENIS" ]; then
        echo "Found potentially lingering ENIs (status available): $LINGERING_ENIS"
        for eni_id in $LINGERING_ENIS; do
            echo "  Attempting to delete ENI: $eni_id..."
            aws ec2 delete-network-interface --network-interface-id $eni_id --region $AWS_REGION || echo "  WARN: Failed to delete ENI $eni_id (might still be detaching or have dependencies). Possible reason: Security Group dependency."
        done
        echo "Waiting 60 seconds after attempting available ENI deletions..."
        sleep 60
    else
        echo "No lingering ENIs found with status 'available'."
    fi
else
    echo "Skipping ENI check: VPC ID missing."
fi

# --- Network Cleanup --- 
echo "\n--- Step 12: Network Resources --- (Security Groups, NAT GW, EIPs, Subnets, RTs, IGW, VPC)"

# 12a. Security Groups (Delete in specific order or handle dependencies)
# It's often easier to delete dependent resources first, then SGs.
SG_LIST=()
[ -n "$ALB_SG_ID_CHK" ] && SG_LIST+=($ALB_SG_ID_CHK)
[ -n "$ECS_SG_ID_CHK" ] && SG_LIST+=($ECS_SG_ID_CHK)
[ -n "$DB_SG_ID_CHK" ] && SG_LIST+=($DB_SG_ID_CHK)
[ -n "$BASTION_SG_ID_CHK" ] && SG_LIST+=($BASTION_SG_ID_CHK)
# Try deleting the specific app SGs first
for sg_id in "${SG_LIST[@]}"; do
   if [[ "$sg_id" != *None* && -n "$sg_id" ]]; then 
        delete_resource "Security Group" $sg_id \
            "aws ec2 delete-security-group --group-id $sg_id --region $AWS_REGION" \
            "aws ec2 describe-security-groups --group-ids $sg_id --region $AWS_REGION" \
            'SecurityGroups[0]'
   fi
done
# Then try deleting the default one created by script 03
if [ -n "$VPC_DEFAULT_SG_ID_CHK" ] && [[ "$VPC_DEFAULT_SG_ID_CHK" != *None* ]]; then
     delete_resource "VPC Default Security Group" $VPC_DEFAULT_SG_ID_CHK \
        "aws ec2 delete-security-group --group-id $VPC_DEFAULT_SG_ID_CHK --region $AWS_REGION" \
        "aws ec2 describe-security-groups --group-ids $VPC_DEFAULT_SG_ID_CHK --region $AWS_REGION" \
        'SecurityGroups[0]'
fi
echo "Waiting 30 seconds after SG deletion attempts for ENI detachment..."
sleep 30

# 12b. NAT Gateway
if [ -n "$NAT_GATEWAY_ID" ]; then
    NAT_GW_CHECK_CMD="aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_GATEWAY_ID --region $AWS_REGION"
    NAT_GW_CHECK_QUERY='NatGateways[?State!=`deleted`]' # Check if not already deleted
    if $NAT_GW_CHECK_CMD --query "$NAT_GW_CHECK_QUERY" --output text 2>/dev/null | grep -q .; then
        delete_resource "NAT Gateway" $NAT_GATEWAY_ID "aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GATEWAY_ID --region $AWS_REGION"
        if [ $? -eq 0 ]; then # Only wait if delete command likely succeeded
            echo "Waiting for NAT Gateway deletion..."
            aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT_GATEWAY_ID --region $AWS_REGION || echo "WARN: Wait for NAT Gateway deletion failed or timed out."
            echo "Waiting additional 60 seconds for NAT Gateway ENI cleanup..."
            sleep 60
        fi
    else
        echo "NAT Gateway $NAT_GATEWAY_ID not found or already deleted."
    fi
fi

# 12c. Elastic IPs (Release)
if [ -n "$EIP_ALLOCATION_ID" ]; then
    delete_resource "NAT Gateway EIP" $EIP_ALLOCATION_ID \
        "aws ec2 release-address --allocation-id $EIP_ALLOCATION_ID --region $AWS_REGION" \
        "aws ec2 describe-addresses --allocation-ids $EIP_ALLOCATION_ID --region $AWS_REGION" \
        'Addresses[0]'
fi
if [ -n "$BASTION_EIP_ALLOCATION_ID" ]; then
    # Disassociate first
    echo "Finding association ID for Bastion EIP $BASTION_EIP_ALLOCATION_ID..."
    ASSOCIATION_ID=$(aws ec2 describe-addresses --allocation-ids $BASTION_EIP_ALLOCATION_ID --query "Addresses[0].AssociationId" --output text --region $AWS_REGION 2>/dev/null)
    if [ -n "$ASSOCIATION_ID" ] && [ "$ASSOCIATION_ID" != "None" ]; then
        echo "Disassociating Bastion EIP (Association ID: $ASSOCIATION_ID)..."
        aws ec2 disassociate-address --association-id $ASSOCIATION_ID --region $AWS_REGION || echo "WARN: Failed to disassociate Bastion EIP."
        sleep 10 # Wait after disassociation
    else
        echo "Bastion EIP not associated or association ID not found."
    fi
    # Now Release
    delete_resource "Bastion EIP" $BASTION_EIP_ALLOCATION_ID \
        "aws ec2 release-address --allocation-id $BASTION_EIP_ALLOCATION_ID --region $AWS_REGION" \
        "aws ec2 describe-addresses --allocation-ids $BASTION_EIP_ALLOCATION_ID --region $AWS_REGION" \
        'Addresses[0]'
fi

# 12d. Subnets
SUBNET_IDS=()
[ -n "$PUBLIC_SUBNET_1_ID" ] && SUBNET_IDS+=($PUBLIC_SUBNET_1_ID)
[ -n "$PUBLIC_SUBNET_2_ID" ] && SUBNET_IDS+=($PUBLIC_SUBNET_2_ID)
[ -n "$PRIVATE_SUBNET_1_ID" ] && SUBNET_IDS+=($PRIVATE_SUBNET_1_ID)
[ -n "$PRIVATE_SUBNET_2_ID" ] && SUBNET_IDS+=($PRIVATE_SUBNET_2_ID)

for subnet_id in "${SUBNET_IDS[@]}"; do
    if [[ "$subnet_id" != *None* && -n "$subnet_id" ]]; then
        delete_resource "Subnet" $subnet_id \
            "aws ec2 delete-subnet --subnet-id $subnet_id --region $AWS_REGION" \
            "aws ec2 describe-subnets --subnet-ids $subnet_id --region $AWS_REGION" \
            'Subnets[0]'
    fi
done

# 12e. Route Tables (Disassociate first if needed, then delete custom ones)
# Disassociations often handled by subnet deletion. Delete custom RTs.
if [ -n "$PUBLIC_RT_ID" ]; then
    delete_resource "Public Route Table" $PUBLIC_RT_ID \
        "aws ec2 delete-route-table --route-table-id $PUBLIC_RT_ID --region $AWS_REGION" \
        "aws ec2 describe-route-tables --route-table-ids $PUBLIC_RT_ID --region $AWS_REGION" \
        'RouteTables[0]'
fi
if [ -n "$PRIVATE_ROUTE_TABLE_ID" ]; then
    delete_resource "Private Route Table" $PRIVATE_ROUTE_TABLE_ID \
        "aws ec2 delete-route-table --route-table-id $PRIVATE_ROUTE_TABLE_ID --region $AWS_REGION" \
        "aws ec2 describe-route-tables --route-table-ids $PRIVATE_ROUTE_TABLE_ID --region $AWS_REGION" \
        'RouteTables[0]'
fi


# 12f. Internet Gateway (Detach first)
if [ -n "$IGW_ID" ] && [ -n "$VPC_ID" ]; then
    # Check if attached before detaching
     if aws ec2 describe-internet-gateways --internet-gateway-ids $IGW_ID --filters Name=attachment.vpc-id,Values=$VPC_ID --query 'InternetGateways[0]' --output text --region $AWS_REGION 2>/dev/null | grep -q .; then
        echo "Detaching Internet Gateway $IGW_ID from VPC $VPC_ID..."
        aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION || echo "WARN: Failed to detach IGW."
        sleep 5 
     else
        echo "Internet Gateway $IGW_ID already detached or not found."
     fi
    delete_resource "Internet Gateway" $IGW_ID \
        "aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $AWS_REGION" \
        "aws ec2 describe-internet-gateways --internet-gateway-ids $IGW_ID --region $AWS_REGION" \
        'InternetGateways[0]'
else
    echo "Skipping IGW detachment/deletion: IGW ID or VPC ID missing."
fi

# 12g. VPC Endpoints (Must be deleted before VPC)
echo "Deleting VPC Endpoints..."
VPC_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC_ID --query "VpcEndpoints[?RequesterManaged==\`false\`].VpcEndpointId" --output text --region $AWS_REGION 2>/dev/null)
if [ -n "$VPC_ENDPOINTS" ]; then
    echo "Found VPC Endpoints: $VPC_ENDPOINTS"
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $VPC_ENDPOINTS --region $AWS_REGION || echo "WARN: Failed to delete some VPC endpoints."
    # Add a loop to wait for endpoints to be fully deleted
    echo "Waiting up to 2 minutes for VPC Endpoints deletion..."
    MAX_WAIT=120
    INTERVAL=10
    ELAPSED=0
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        REMAINING_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $VPC_ENDPOINTS --query "VpcEndpoints[?State!=\`deleted\`].VpcEndpointId" --output text --region $AWS_REGION 2>/dev/null)
        if [ -z "$REMAINING_ENDPOINTS" ]; then
            echo "All specified VPC Endpoints appear deleted."
            break
        fi
        echo "Still waiting for endpoints: $REMAINING_ENDPOINTS... ($ELAPSED/$MAX_WAIT sec)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "WARN: Timed out waiting for VPC Endpoints to delete. Remaining: $REMAINING_ENDPOINTS"
    fi
    echo "Waiting additional 90 seconds after VPC Endpoint deletion attempt for ENI cleanup..."
    sleep 90 
else
    echo "No VPC Endpoints found for VPC $VPC_ID."
fi


# 12h. VPC
# Note: This will fail if *any* dependent resources remain (SGs, Endpoints, Subnets, RTs, IGW etc.)
if [ -n "$VPC_ID" ]; then
    delete_resource "VPC" $VPC_ID \
        "aws ec2 delete-vpc --vpc-id $VPC_ID --region $AWS_REGION" \
        "aws ec2 describe-vpcs --vpc-ids $VPC_ID --region $AWS_REGION" \
        'Vpcs[0]'
fi

# 13. Optional: Delete SSM Parameters
# echo "\n--- Step 13: SSM Parameters (Optional) ---"
# READ_PARAMS=false # Set to true to enable parameter deletion prompt
# if [ "$READ_PARAMS" = true ] && [ -n "$SECRET_PARAMETER_PATH_PREFIX" ]; then
#     read -p "Delete SSM parameters with prefix '${SECRET_PARAMETER_PATH_PREFIX}'? (yes/no): " DEL_PARAMS
#     if [ "$DEL_PARAMS" == "yes" ]; then
#         echo "Finding SSM parameters with prefix $SECRET_PARAMETER_PATH_PREFIX ..."
#         PARAM_NAMES=$(aws ssm get-parameters-by-path --path "$SECRET_PARAMETER_PATH_PREFIX" --recursive --query "Parameters[*].Name" --output text --region $AWS_REGION)
#         if [ -n "$PARAM_NAMES" ]; then
#              # AWS CLI delete-parameters takes space-separated names
#              PARAM_NAMES_SPACE_SEP=$(echo $PARAM_NAMES) 
#              echo "Deleting parameters: $PARAM_NAMES_SPACE_SEP"
#              aws ssm delete-parameters --names $PARAM_NAMES_SPACE_SEP --region $AWS_REGION || echo "WARN: Failed to delete some or all SSM parameters."
#              echo "SSM Parameter deletion initiated."
#         else
#              echo "No parameters found with prefix $SECRET_PARAMETER_PATH_PREFIX."
#         fi
#     else 
#         echo "Skipping SSM parameter deletion."
#     fi
# elif [ "$READ_PARAMS" = true ]; then
#      echo "Skipping SSM parameter deletion: Prefix not found in config."
# fi

# 14. Cleanup local config files
echo "\n--- Final Step: Local Config Files ---"
CONFIG_FILES_TO_DELETE=("vpc-config.sh" "rds-config.sh" "ecr-config.sh" "certificate-config.sh" "alb-config.sh" "nat-gateway-config.sh" "secrets-config.sh" "bastion-config.sh" "ecs-config.sh") 
read -p "Delete local configuration files in '$CONFIG_DIR'? (yes/no): " DEL_CONFIG
if [ "$DEL_CONFIG" == "yes" ]; then
    echo "Deleting config files from $CONFIG_DIR..."
    for cfg in "${CONFIG_FILES_TO_DELETE[@]}"; do
        if [ -f "$CONFIG_DIR/$cfg" ]; then
            rm -v "$CONFIG_DIR/$cfg"
        fi
    done
    # Delete temp files too
    rm -f "$SCRIPT_DIR/"*.tmp
    rm -f "$SCRIPT_DIR/"*.json # Remove any leftover json files
    echo "Local config files deleted."
else
    echo "Skipping deletion of local config files."
fi

echo "Cleanup Script Finished."

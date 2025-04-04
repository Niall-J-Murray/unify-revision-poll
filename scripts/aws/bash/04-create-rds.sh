#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"
# Config files should exist from previous step, no need to mkdir -p here

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$CONFIG_DIR/vpc-config.sh"

echo "Creating RDS PostgreSQL database..."

# Check/Create security group for RDS
DB_SG_NAME="${APP_NAME}-rds-sg" # Use consistent naming
echo "Checking for existing DB Security Group: $DB_SG_NAME..."

# Attempt to describe the security group
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=$DB_SG_NAME Name=vpc-id,Values=$VPC_ID \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --region $AWS_REGION 2>/dev/null) # Redirect stderr to avoid error message if not found

# If SG ID is empty or "None", create the group
if [ -z "$SECURITY_GROUP_ID" ] || [ "$SECURITY_GROUP_ID" == "None" ]; then
  echo "DB Security Group not found. Creating..."
  SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name $DB_SG_NAME \
    --description "Security group for ${APP_NAME} RDS" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=AppName,Value='$APP_NAME'}]')

  if [ $? -ne 0 ] || [ -z "$SECURITY_GROUP_ID" ]; then echo "Failed to create DB Security Group"; exit 1; fi
  echo "Created DB security group: $SECURITY_GROUP_ID"
else
  echo "Found existing DB security group: $SECURITY_GROUP_ID"
fi

# Configure security group rules (or lack thereof, as ingress is added later)
echo "DB Security Group created/verified. Ingress rule from App SG will be added later."

# Create or Update DB subnet group
DB_SUBNET_GROUP_NAME="${APP_NAME}-subnet-group"
echo "Checking/Updating DB Subnet Group: $DB_SUBNET_GROUP_NAME..."

# Check if the subnet group exists
EXISTING_SUBNET_GROUP_INFO=$(aws rds describe-db-subnet-groups --db-subnet-group-name $DB_SUBNET_GROUP_NAME --region $AWS_REGION 2>/dev/null)

if [ $? -ne 0 ]; then
  # Subnet group does not exist, create it
  echo "DB Subnet Group '$DB_SUBNET_GROUP_NAME' not found. Creating..."
  aws rds create-db-subnet-group \
    --db-subnet-group-name $DB_SUBNET_GROUP_NAME \
    --subnet-ids "$PRIVATE_SUBNET_1_ID" "$PRIVATE_SUBNET_2_ID" \
    --db-subnet-group-description "Subnet group for ${APP_NAME} RDS" \
    --tags Key=Name,Value=$DB_SUBNET_GROUP_NAME Key=AppName,Value=$APP_NAME \
    --region $AWS_REGION # Added region flag
  if [ $? -ne 0 ]; then echo "Failed to create DB Subnet Group"; exit 1; fi
  echo "DB Subnet Group created."
else
  # Subnet group exists, check if it belongs to the correct VPC
  echo "DB Subnet Group '$DB_SUBNET_GROUP_NAME' already exists. Checking VPC ID..."
  EXISTING_VPC_ID=$(echo "$EXISTING_SUBNET_GROUP_INFO" | jq -r '.DBSubnetGroups[0].VpcId')
  
  if [ "$EXISTING_VPC_ID" == "$VPC_ID" ]; then
    # VPC IDs match, safe to modify
    echo "Existing subnet group is in the correct VPC ($VPC_ID). Updating with current private subnets..."
    aws rds modify-db-subnet-group \
      --db-subnet-group-name $DB_SUBNET_GROUP_NAME \
      --subnet-ids "$PRIVATE_SUBNET_1_ID" "$PRIVATE_SUBNET_2_ID" \
      --db-subnet-group-description "Subnet group for ${APP_NAME} RDS" \
      --region $AWS_REGION # Added region flag
    if [ $? -ne 0 ]; then echo "Failed to modify DB Subnet Group"; exit 1; fi
    echo "DB Subnet Group updated successfully."
  else
    # VPC IDs DO NOT match - this is an orphaned group from a previous VPC
    echo "Error: Existing DB Subnet Group '$DB_SUBNET_GROUP_NAME' belongs to a different VPC ($EXISTING_VPC_ID) than the current VPC ($VPC_ID)."
    echo "This indicates an orphaned resource from a previous deployment."
    echo "Attempting to delete the orphaned subnet group..."
    aws rds delete-db-subnet-group --db-subnet-group-name $DB_SUBNET_GROUP_NAME --region $AWS_REGION
    if [ $? -ne 0 ]; then
      echo "Error: Failed to delete orphaned DB Subnet Group '$DB_SUBNET_GROUP_NAME'. It might still be associated with an RDS instance."
      echo "Please manually delete the subnet group and any associated RDS instances from VPC '$EXISTING_VPC_ID' before re-running."
      exit 1
    else
      echo "Orphaned DB Subnet Group deleted. Re-running the script should now create a new one in the correct VPC."
      echo "Please re-run the deployment script (00-deploy-all.sh)."
      exit 1 # Exit cleanly asking the user to re-run
    fi
  fi
fi

# --- Check/Create RDS Instance --- 
echo "Checking for existing RDS instance: ${APP_NAME}-db..."
DB_INSTANCE_INFO=$(aws rds describe-db-instances --db-instance-identifier "${APP_NAME}-db" --region $AWS_REGION 2>/dev/null)

if [ $? -eq 0 ]; then
    # Instance exists, extract info
    DB_INSTANCE_STATUS=$(echo "$DB_INSTANCE_INFO" | jq -r '.DBInstances[0].DBInstanceStatus')
    RDS_ENDPOINT=$(echo "$DB_INSTANCE_INFO" | jq -r '.DBInstances[0].Endpoint.Address')
    echo "Found existing RDS instance ${APP_NAME}-db with status: $DB_INSTANCE_STATUS"

    # Wait if it's not available
    if [ "$DB_INSTANCE_STATUS" != "available" ]; then
        echo "Waiting for instance ${APP_NAME}-db to become available..."
        aws rds wait db-instance-available --db-instance-identifier "${APP_NAME}-db" --region $AWS_REGION
        if [ $? -ne 0 ]; then
            echo "Error: Wait failed. Instance ${APP_NAME}-db did not become available."
            exit 1
        fi
        # Re-fetch endpoint after becoming available (might not be present during creation)
        RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "${APP_NAME}-db" --query 'DBInstances[0].Endpoint.Address' --output text --region $AWS_REGION)
        echo "Instance ${APP_NAME}-db is now available."
    fi
    if [ -z "$RDS_ENDPOINT" ] || [ "$RDS_ENDPOINT" == "None" ]; then
         echo "Error: Could not retrieve endpoint address for existing instance ${APP_NAME}-db."
         exit 1
    fi
else
    # Instance does not exist, create it
    echo "RDS instance ${APP_NAME}-db not found. Creating..."
    aws rds create-db-instance \
      --db-instance-identifier "${APP_NAME}-db" \
      --db-instance-class $DB_INSTANCE_CLASS \
      --engine postgres \
      --engine-version $DB_ENGINE_VERSION \
      --allocated-storage $DB_ALLOCATED_STORAGE \
      --db-name $DB_NAME \
      --master-username $DB_USERNAME \
      --master-user-password $DB_PASSWORD \
      --vpc-security-group-ids $SECURITY_GROUP_ID \
      --db-subnet-group-name $DB_SUBNET_GROUP_NAME \
      --no-publicly-accessible \
      --backup-retention-period 7 \
      --port 5432 \
      --no-multi-az \
      --storage-type gp3 \
      --no-enable-iam-database-authentication \
      --no-enable-performance-insights \
      --no-auto-minor-version-upgrade \
      --copy-tags-to-snapshot \
      --no-deletion-protection \
      --region $AWS_REGION \
      --tags Key=AppName,Value=$APP_NAME

    if [ $? -ne 0 ]; then echo "Failed to start creating RDS instance"; exit 1; fi

    echo "Waiting for instance ${APP_NAME}-db to become available (this can take 5-10 minutes)..."
    aws rds wait db-instance-available --db-instance-identifier "${APP_NAME}-db" --region $AWS_REGION
    if [ $? -ne 0 ]; then
        echo "Error: Wait failed. Instance ${APP_NAME}-db did not become available after creation."
        # Attempt to describe anyway in case wait failed but instance is usable
        DB_INSTANCE_INFO=$(aws rds describe-db-instances --db-instance-identifier "${APP_NAME}-db" --region $AWS_REGION 2>/dev/null)
        if [ $? -ne 0 ]; then
             echo "Could not describe instance after failed wait. Exiting."
             exit 1
        fi
    fi
    echo "Instance ${APP_NAME}-db is now available."
    # Get endpoint after creation
    RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "${APP_NAME}-db" --query 'DBInstances[0].Endpoint.Address' --output text --region $AWS_REGION)
     if [ -z "$RDS_ENDPOINT" ] || [ "$RDS_ENDPOINT" == "None" ]; then
         echo "Error: Could not retrieve endpoint address after creating instance ${APP_NAME}-db."
         exit 1
    fi
fi
# --- End Check/Create RDS Instance ---

echo "RDS instance endpoint: $RDS_ENDPOINT"

# Save RDS configuration to a file (Ensure SECURITY_GROUP_ID is saved)
RDS_CONFIG_FILE="$CONFIG_DIR/rds-config.sh"
cat > "$RDS_CONFIG_FILE" << EOF
#!/bin/bash

# RDS Configuration
export RDS_ENDPOINT=$RDS_ENDPOINT
export SECURITY_GROUP_ID=$SECURITY_GROUP_ID # <-- Ensure this is saved
export DB_NAME=$DB_NAME
export DB_USERNAME=$DB_USERNAME # <-- Use the variable, not hardcoded 'admin'
export DB_PASSWORD=\'$DB_PASSWORD\' # <-- Use single quotes to preserve special chars if any
EOF

chmod +x "$RDS_CONFIG_FILE"

echo "RDS configuration saved to $RDS_CONFIG_FILE"
echo "RDS creation completed!" 
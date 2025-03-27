#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$SCRIPT_DIR/vpc-config.sh"

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
aws rds describe-db-subnet-groups --db-subnet-group-name $DB_SUBNET_GROUP_NAME --region $AWS_REGION > /dev/null 2>&1

if [ $? -ne 0 ]; then
  # Subnet group does not exist, create it
  echo "DB Subnet Group '$DB_SUBNET_GROUP_NAME' not found. Creating..."
  aws rds create-db-subnet-group \
    --db-subnet-group-name $DB_SUBNET_GROUP_NAME \
    --subnet-ids "$PRIVATE_SUBNET_1_ID" "$PRIVATE_SUBNET_2_ID" \
    --db-subnet-group-description "Subnet group for ${APP_NAME} RDS" \
    --tags Key=Name,Value=$DB_SUBNET_GROUP_NAME Key=AppName,Value=$APP_NAME
  if [ $? -ne 0 ]; then echo "Failed to create DB Subnet Group"; exit 1; fi
  echo "DB Subnet Group created."
else
  # Subnet group exists, update it to ensure correct subnets are used
  echo "DB Subnet Group '$DB_SUBNET_GROUP_NAME' already exists. Updating with current private subnets..."
  aws rds modify-db-subnet-group \
    --db-subnet-group-name $DB_SUBNET_GROUP_NAME \
    --subnet-ids "$PRIVATE_SUBNET_1_ID" "$PRIVATE_SUBNET_2_ID" \
    --db-subnet-group-description "Subnet group for ${APP_NAME} RDS" # Description update is optional but good practice
  if [ $? -ne 0 ]; then echo "Failed to modify DB Subnet Group"; exit 1; fi
  echo "DB Subnet Group updated successfully."
fi

# Create RDS instance
DB_INSTANCE_IDENTIFIER="${APP_NAME}-db" # Use consistent identifier
echo "Creating RDS Instance (Single-AZ for cost saving) using username '$DB_USERNAME'..."
aws rds create-db-instance \
  --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
  --db-name $DB_NAME \
  --db-instance-class $DB_INSTANCE_CLASS \
  --engine $DB_ENGINE \
  --engine-version $DB_ENGINE_VERSION \
  --master-username "$DB_USERNAME" \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage $DB_ALLOCATED_STORAGE \
  --db-subnet-group-name $DB_SUBNET_GROUP_NAME \
  --vpc-security-group-ids $SECURITY_GROUP_ID \
  --region $AWS_REGION \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-05:00" \
  --preferred-maintenance-window "sun:05:00-sun:07:00" \
  --no-publicly-accessible \
  --tags Key=Name,Value=$DB_INSTANCE_IDENTIFIER Key=AppName,Value=$APP_NAME

# ===>>> Add error check immediately after creation attempt <<<===
if [ $? -ne 0 ]; then
    echo "!!! Failed to initiate RDS Instance creation. Please check the AWS error message above. !!!"
    exit 1
fi

echo "RDS instance creation initiated. This may take several minutes."
echo "You can check the status in the AWS RDS Console."

# Wait for the RDS instance to become available
echo "Waiting for RDS instance to become available..."
aws rds wait db-instance-available --db-instance-identifier ${APP_NAME}-db

# Get the RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier ${APP_NAME}-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "RDS endpoint: $RDS_ENDPOINT"

# Save RDS configuration to a file (Ensure SECURITY_GROUP_ID is saved)
cat > "$SCRIPT_DIR/rds-config.sh" << EOF
#!/bin/bash

# RDS Configuration
export RDS_ENDPOINT=$RDS_ENDPOINT
export SECURITY_GROUP_ID=$SECURITY_GROUP_ID # <-- Ensure this is saved
export DB_NAME=$DB_NAME
export DB_USERNAME=$DB_USERNAME # <-- Use the variable, not hardcoded 'admin'
export DB_PASSWORD='$DB_PASSWORD' # <-- Use single quotes to preserve special chars if any
EOF

chmod +x "$SCRIPT_DIR/rds-config.sh"

echo "RDS configuration saved to $SCRIPT_DIR/rds-config.sh"
echo "RDS creation completed!" 
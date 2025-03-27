#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$SCRIPT_DIR/vpc-config.sh"

echo "Creating RDS PostgreSQL database..."

# Create security group for RDS
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name ${APP_NAME}-rds-sg \
  --description "Security group for RDS" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

echo "Created security group: $SECURITY_GROUP_ID"

# Configure security group rules
aws ec2 authorize-security-group-ingress \
  --group-id $SECURITY_GROUP_ID \
  --protocol tcp \
  --port 5432 \
  --cidr $VPC_CIDR

# Create DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name ${APP_NAME}-subnet-group \
  --subnet-ids $PRIVATE_SUBNET_1_ID $PRIVATE_SUBNET_2_ID \
  --db-subnet-group-description "Subnet group for RDS" \
  --tags Key=Name,Value=${APP_NAME}-subnet-group

# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier ${APP_NAME}-db \
  --db-name $DB_NAME \
  --db-instance-class $DB_INSTANCE_CLASS \
  --engine $DB_ENGINE \
  --engine-version $DB_ENGINE_VERSION \
  --master-username $DB_USERNAME \
  --master-user-password $DB_PASSWORD \
  --allocated-storage $DB_ALLOCATED_STORAGE \
  --vpc-security-group-ids $SECURITY_GROUP_ID \
  --db-subnet-group-name ${APP_NAME}-subnet-group \
  --backup-retention-period 7 \
  --no-publicly-accessible \
  --no-auto-minor-version-upgrade \
  --tags Key=Name,Value=${APP_NAME}-db

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

# Save RDS configuration to a file
cat > "$SCRIPT_DIR/rds-config.sh" << EOF
#!/bin/bash

# RDS Configuration
export RDS_ENDPOINT=$RDS_ENDPOINT
export SECURITY_GROUP_ID=$SECURITY_GROUP_ID
export DB_NAME=$DB_NAME
export DB_USERNAME=$DB_USERNAME
export DB_PASSWORD=$DB_PASSWORD
EOF

chmod +x "$SCRIPT_DIR/rds-config.sh"

echo "RDS configuration saved to $SCRIPT_DIR/rds-config.sh"
echo "RDS creation completed!" 
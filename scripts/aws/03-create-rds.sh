#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$SCRIPT_DIR/vpc-config.sh"

echo "Creating RDS PostgreSQL database..."

# Create security group for RDS
DB_SG_ID=$(aws ec2 create-security-group \
  --group-name ${APP_NAME}-db-sg \
  --description "Security group for ${APP_NAME} database" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text \
  --region $AWS_REGION)

echo "Created DB security group: $DB_SG_ID"

# Allow PostgreSQL traffic from anywhere (public access)
aws ec2 authorize-security-group-ingress \
  --group-id $DB_SG_ID \
  --protocol tcp \
  --port $DB_PORT \
  --cidr 0.0.0.0/0 \
  --region $AWS_REGION

echo "Configured DB security group ingress rules"

# Create DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name ${APP_NAME}-db-subnet-group \
  --db-subnet-group-description "Subnet group for ${APP_NAME} database" \
  --subnet-ids $PUBLIC_SUBNET_1_ID $PUBLIC_SUBNET_2_ID \
  --region $AWS_REGION

echo "Created DB subnet group"

# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier ${APP_NAME}-db \
  --db-instance-class $DB_INSTANCE_CLASS \
  --engine postgres \
  --master-username $DB_USERNAME \
  --master-user-password $DB_PASSWORD \
  --allocated-storage $DB_ALLOCATED_STORAGE \
  --db-name $DB_NAME \
  --vpc-security-group-ids $DB_SG_ID \
  --db-subnet-group-name ${APP_NAME}-db-subnet-group \
  --publicly-accessible \
  --no-multi-az \
  --backup-retention-period 7 \
  --preferred-backup-window 03:00-04:00 \
  --no-auto-minor-version-upgrade \
  --port $DB_PORT \
  --region $AWS_REGION

echo "Creating RDS instance, waiting for it to become available..."
echo "This may take up to 10-15 minutes..."

# Wait for the RDS instance to be available
aws rds wait db-instance-available \
  --db-instance-identifier ${APP_NAME}-db \
  --region $AWS_REGION

# Get the RDS endpoint
DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier ${APP_NAME}-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region $AWS_REGION)

echo "RDS instance is available at: $DB_ENDPOINT"

# Save RDS configuration to a file
cat > "$SCRIPT_DIR/rds-config.sh" << EOF
#!/bin/bash

# RDS Configuration
export DB_SG_ID=$DB_SG_ID
export DB_ENDPOINT=$DB_ENDPOINT
EOF

chmod +x "$SCRIPT_DIR/rds-config.sh"

echo "RDS configuration saved to $SCRIPT_DIR/rds-config.sh"
echo "Database username: $DB_USERNAME"
echo "Database password: $DB_PASSWORD (Keep this secure!)"
echo "Database name: $DB_NAME"
echo "RDS creation completed" 
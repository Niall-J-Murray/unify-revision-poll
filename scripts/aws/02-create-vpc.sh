#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"

echo "Creating VPC infrastructure..."

# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${APP_NAME}-vpc}]" \
  --query 'Vpc.VpcId' \
  --output text \
  --region $AWS_REGION)

echo "Created VPC: $VPC_ID"

# Enable DNS hostname support for the VPC
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames \
  --region $AWS_REGION

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${APP_NAME}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text \
  --region $AWS_REGION)

echo "Created Internet Gateway: $IGW_ID"

# Attach Internet Gateway to VPC
aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID \
  --region $AWS_REGION

echo "Attached Internet Gateway to VPC"

# Create public route table
PUBLIC_ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${APP_NAME}-public-rt}]" \
  --query 'RouteTable.RouteTableId' \
  --output text \
  --region $AWS_REGION)

echo "Created public route table: $PUBLIC_ROUTE_TABLE_ID"

# Create route to Internet Gateway
aws ec2 create-route \
  --route-table-id $PUBLIC_ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $AWS_REGION

echo "Created route to Internet Gateway"

# Create public subnets
PUBLIC_SUBNET_1_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PUBLIC_SUBNET_1_CIDR \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-public-1}]" \
  --query 'Subnet.SubnetId' \
  --output text \
  --region $AWS_REGION)

echo "Created public subnet 1: $PUBLIC_SUBNET_1_ID"

PUBLIC_SUBNET_2_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PUBLIC_SUBNET_2_CIDR \
  --availability-zone ${AWS_REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-public-2}]" \
  --query 'Subnet.SubnetId' \
  --output text \
  --region $AWS_REGION)

echo "Created public subnet 2: $PUBLIC_SUBNET_2_ID"

# Associate public subnets with public route table
aws ec2 associate-route-table \
  --route-table-id $PUBLIC_ROUTE_TABLE_ID \
  --subnet-id $PUBLIC_SUBNET_1_ID \
  --region $AWS_REGION

aws ec2 associate-route-table \
  --route-table-id $PUBLIC_ROUTE_TABLE_ID \
  --subnet-id $PUBLIC_SUBNET_2_ID \
  --region $AWS_REGION

echo "Associated public subnets with route table"

# Enable auto-assign public IP for public subnets
aws ec2 modify-subnet-attribute \
  --subnet-id $PUBLIC_SUBNET_1_ID \
  --map-public-ip-on-launch \
  --region $AWS_REGION

aws ec2 modify-subnet-attribute \
  --subnet-id $PUBLIC_SUBNET_2_ID \
  --map-public-ip-on-launch \
  --region $AWS_REGION

echo "Enabled auto-assign public IP for public subnets"

# Create private subnets
PRIVATE_SUBNET_1_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SUBNET_1_CIDR \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-private-1}]" \
  --query 'Subnet.SubnetId' \
  --output text \
  --region $AWS_REGION)

echo "Created private subnet 1: $PRIVATE_SUBNET_1_ID"

PRIVATE_SUBNET_2_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $PRIVATE_SUBNET_2_CIDR \
  --availability-zone ${AWS_REGION}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-private-2}]" \
  --query 'Subnet.SubnetId' \
  --output text \
  --region $AWS_REGION)

echo "Created private subnet 2: $PRIVATE_SUBNET_2_ID"

# Save IDs to a config file for later scripts
cat > "$SCRIPT_DIR/vpc-config.sh" << EOF
#!/bin/bash

# VPC Configuration
export VPC_ID=$VPC_ID
export IGW_ID=$IGW_ID
export PUBLIC_ROUTE_TABLE_ID=$PUBLIC_ROUTE_TABLE_ID
export PUBLIC_SUBNET_1_ID=$PUBLIC_SUBNET_1_ID
export PUBLIC_SUBNET_2_ID=$PUBLIC_SUBNET_2_ID
export PRIVATE_SUBNET_1_ID=$PRIVATE_SUBNET_1_ID
export PRIVATE_SUBNET_2_ID=$PRIVATE_SUBNET_2_ID
EOF

chmod +x "$SCRIPT_DIR/vpc-config.sh"

echo "VPC configuration saved to $SCRIPT_DIR/vpc-config.sh"
echo "VPC infrastructure creation completed" 
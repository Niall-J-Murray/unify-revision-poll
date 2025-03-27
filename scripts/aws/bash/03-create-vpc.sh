#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"

echo "Creating VPC resources..."

# Check/Create VPC
# ... (VPC check/create logic - assuming this exists or add similarly) ...
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values="${APP_NAME}-vpc" Name=cidr,Values=$VPC_CIDR --query 'Vpcs[0].VpcId' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
  echo "Creating VPC..."
  VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --query 'Vpc.VpcId' --output text --region $AWS_REGION)
  aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value="${APP_NAME}-vpc" --region $AWS_REGION
  aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames '{"Value":true}' --region $AWS_REGION
  echo "VPC created with ID: $VPC_ID"
else
  echo "Found existing VPC: $VPC_ID"
fi

# Check/Create Internet Gateway
# ... (IGW check/create/attach logic - assuming this exists or add similarly) ...
IGW_ID=$(aws ec2 describe-internet-gateways --filters Name=tag:Name,Values="${APP_NAME}-igw" Name=attachment.vpc-id,Values=$VPC_ID --query 'InternetGateways[0].InternetGatewayId' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$IGW_ID" ] || [ "$IGW_ID" == "None" ]; then
    echo "Creating Internet Gateway..."
    IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --region $AWS_REGION)
    aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value="${APP_NAME}-igw" --region $AWS_REGION
    aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --region $AWS_REGION
    echo "Internet Gateway created and attached: $IGW_ID"
else
    echo "Found existing Internet Gateway: $IGW_ID"
fi


# Check/Create Public Route Table and Route
# ... (Public RT check/create/route logic - assuming this exists or add similarly) ...
PUBLIC_RT_ID=$(aws ec2 describe-route-tables --filters Name=tag:Name,Values="${APP_NAME}-public-rt" Name=vpc-id,Values=$VPC_ID --query 'RouteTables[0].RouteTableId' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$PUBLIC_RT_ID" ] || [ "$PUBLIC_RT_ID" == "None" ]; then
    echo "Creating Public Route Table..."
    PUBLIC_RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --region $AWS_REGION)
    aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value="${APP_NAME}-public-rt" --region $AWS_REGION
    aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $AWS_REGION
    echo "Public Route Table created: $PUBLIC_RT_ID"
else
    echo "Found existing Public Route Table: $PUBLIC_RT_ID"
fi

# --- Function to Check/Create Subnet ---
check_create_subnet() {
  local subnet_name=$1
  local cidr_block=$2
  local az=$3
  local subnet_var_name=$4 # Name of the variable to store the ID (e.g., PUBLIC_SUBNET_1_ID)
  local route_table_id=$5 # Optional: Route table to associate

  echo "Checking for subnet: $subnet_name in AZ $az..."
  SUBNET_ID=$(aws ec2 describe-subnets \
    --filters Name=tag:Name,Values="$subnet_name" Name=vpc-id,Values=$VPC_ID Name=cidr-block,Values="$cidr_block" Name=availability-zone,Values="$az" \
    --query 'Subnets[0].SubnetId' --output text --region $AWS_REGION 2>/dev/null)

  if [ -z "$SUBNET_ID" ] || [ "$SUBNET_ID" == "None" ]; then
    echo "Subnet $subnet_name not found. Creating..."
    SUBNET_ID=$(aws ec2 create-subnet \
      --vpc-id $VPC_ID \
      --cidr-block "$cidr_block" \
      --availability-zone "$az" \
      --query 'Subnet.SubnetId' \
      --output text \
      --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$SUBNET_ID" ]; then echo "Failed to create subnet $subnet_name"; exit 1; fi
    aws ec2 create-tags --resources $SUBNET_ID --tags Key=Name,Value="$subnet_name" --region $AWS_REGION
    echo "Created subnet $subnet_name with ID: $SUBNET_ID"

    # Associate route table if provided
    if [ -n "$route_table_id" ]; then
        echo "Associating Route Table $route_table_id with $subnet_name..."
        aws ec2 associate-route-table --subnet-id $SUBNET_ID --route-table-id $route_table_id --region $AWS_REGION
        if [ $? -ne 0 ]; then echo "Failed to associate route table with $subnet_name"; exit 1; fi # Add error check
    fi
  else
    echo "Found existing subnet $subnet_name: $SUBNET_ID"
  fi
  # Export the variable dynamically
  export "$subnet_var_name=$SUBNET_ID"
  # Also save to vpc-config.sh for persistence
  echo "export $subnet_var_name=\"$SUBNET_ID\"" >> "$SCRIPT_DIR/vpc-config.sh.tmp"
}

# --- Create Subnets ---
echo "#!/bin/bash" > "$SCRIPT_DIR/vpc-config.sh.tmp" # Start with a clean temp file
echo "export VPC_ID=\"$VPC_ID\"" >> "$SCRIPT_DIR/vpc-config.sh.tmp"

# Public Subnets (Keep in a/b for simplicity, or change if needed)
check_create_subnet "${APP_NAME}-public-subnet-1" "$PUBLIC_SUBNET_1_CIDR" "${AWS_REGION}a" "PUBLIC_SUBNET_1_ID" "$PUBLIC_RT_ID"
check_create_subnet "${APP_NAME}-public-subnet-2" "$PUBLIC_SUBNET_2_CIDR" "${AWS_REGION}b" "PUBLIC_SUBNET_2_ID" "$PUBLIC_RT_ID"

# Private Subnets (Use AZs with capacity: eu-west-1a, eu-west-1b)
check_create_subnet "${APP_NAME}-private-subnet-1" "$PRIVATE_SUBNET_1_CIDR" "${AWS_REGION}a" "PRIVATE_SUBNET_1_ID" # <-- Use eu-west-1a
check_create_subnet "${APP_NAME}-private-subnet-2" "$PRIVATE_SUBNET_2_CIDR" "${AWS_REGION}b" "PRIVATE_SUBNET_2_ID" # <-- Use eu-west-1b
# Note: Private subnets typically need a NAT Gateway and a private route table, which are not shown here for brevity.

# Replace old config file with the new one
mv "$SCRIPT_DIR/vpc-config.sh.tmp" "$SCRIPT_DIR/vpc-config.sh"
chmod +x "$SCRIPT_DIR/vpc-config.sh"

echo "VPC configuration saved to $SCRIPT_DIR/vpc-config.sh"
echo "VPC setup script completed." 
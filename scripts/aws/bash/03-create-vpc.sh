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

# --- NEW: Allocate Elastic IP for NAT Gateway ---
echo "Checking/Allocating Elastic IP for NAT Gateway..."
# Check if we already stored an allocation ID
if [ -f "$SCRIPT_DIR/nat-gateway-config.sh" ]; then
    source "$SCRIPT_DIR/nat-gateway-config.sh" # Loads EIP_ALLOCATION_ID
fi

# Try to describe the EIP using the stored ID
EIP_EXISTS=false
if [ ! -z "$EIP_ALLOCATION_ID" ]; then
    EIP_ADDRESS=$(aws ec2 describe-addresses --allocation-ids $EIP_ALLOCATION_ID --query 'Addresses[0].PublicIp' --output text --region $AWS_REGION 2>/dev/null)
    if [ $? -eq 0 ] && [ ! -z "$EIP_ADDRESS" ]; then
        echo "Found existing Elastic IP: $EIP_ADDRESS (Allocation ID: $EIP_ALLOCATION_ID)"
        EIP_EXISTS=true
    else
        echo "Stored EIP Allocation ID $EIP_ALLOCATION_ID not found or invalid. Will allocate a new one."
        # Clear the variable so we allocate a new one
        EIP_ALLOCATION_ID="" 
    fi
fi

# Allocate if it doesn't exist or wasn't found
if [ "$EIP_EXISTS" = false ]; then
    echo "Allocating new Elastic IP..."
    ALLOCATION_RESULT=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$ALLOCATION_RESULT" ]; then echo "Failed to allocate Elastic IP"; exit 1; fi
    EIP_ALLOCATION_ID=$ALLOCATION_RESULT
    echo "Allocated Elastic IP with Allocation ID: $EIP_ALLOCATION_ID"
    # Save the new ID
    echo "export EIP_ALLOCATION_ID=\"$EIP_ALLOCATION_ID\"" > "$SCRIPT_DIR/nat-gateway-config.sh"
    chmod +x "$SCRIPT_DIR/nat-gateway-config.sh"
fi
# --- End EIP Allocation ---

# --- NEW: Check/Create NAT Gateway in Public Subnet 1 ---
echo "Checking/Creating NAT Gateway..."
# Check if we already stored a NAT Gateway ID
if [ -f "$SCRIPT_DIR/nat-gateway-config.sh" ]; then
    source "$SCRIPT_DIR/nat-gateway-config.sh" # Ensure latest ID is loaded
fi

# Try to describe the NAT Gateway using the stored ID
NAT_GATEWAY_ID_FOUND=""
if [ ! -z "$NAT_GATEWAY_ID" ]; then
    GW_STATE=$(aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_GATEWAY_ID --query 'NatGateways[0].State' --output text --region $AWS_REGION 2>/dev/null)
    if [ $? -eq 0 ] && [ "$GW_STATE" != "deleted" ] && [ "$GW_STATE" != "failed" ]; then
        echo "Found existing NAT Gateway: $NAT_GATEWAY_ID (State: $GW_STATE)"
        NAT_GATEWAY_ID_FOUND=$NAT_GATEWAY_ID
    else
        echo "Stored NAT Gateway ID $NAT_GATEWAY_ID not found or in unusable state. Will create a new one."
         # Clear the variable so we create a new one
        NAT_GATEWAY_ID=""
    fi
fi

# Create if it doesn't exist or wasn't found usable
if [ -z "$NAT_GATEWAY_ID_FOUND" ]; then
    echo "Creating NAT Gateway in Public Subnet 1 ($PUBLIC_SUBNET_1_ID)..."
    CREATE_NAT_RESULT=$(aws ec2 create-nat-gateway \
      --subnet-id $PUBLIC_SUBNET_1_ID \
      --allocation-id $EIP_ALLOCATION_ID \
      --query 'NatGateway.NatGatewayId' \
      --output text \
      --tag-specifications 'ResourceType=natgateway,Tags=[{Key=AppName,Value='$APP_NAME'}]' \
      --region $AWS_REGION)

    if [ $? -ne 0 ] || [ -z "$CREATE_NAT_RESULT" ]; then echo "Failed to create NAT Gateway"; exit 1; fi
    NAT_GATEWAY_ID=$CREATE_NAT_RESULT
    echo "Created NAT Gateway: $NAT_GATEWAY_ID. Waiting for it to become available..."

    # Save the new ID immediately
    # Use grep to update or add the NAT_GATEWAY_ID line in the config file
    if grep -q "export NAT_GATEWAY_ID=" "$SCRIPT_DIR/nat-gateway-config.sh"; then
        sed -i "s/^export NAT_GATEWAY_ID=.*$/export NAT_GATEWAY_ID=\"$NAT_GATEWAY_ID\"/" "$SCRIPT_DIR/nat-gateway-config.sh"
    else
        echo "export NAT_GATEWAY_ID=\"$NAT_GATEWAY_ID\"" >> "$SCRIPT_DIR/nat-gateway-config.sh"
    fi

    # Wait for the NAT Gateway to be available
    aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GATEWAY_ID --region $AWS_REGION
    if [ $? -ne 0 ]; then echo "NAT Gateway $NAT_GATEWAY_ID failed to become available."; exit 1; fi
    echo "NAT Gateway $NAT_GATEWAY_ID is available."
else
     NAT_GATEWAY_ID=$NAT_GATEWAY_ID_FOUND # Use the found ID
     # If it exists but isn't available yet, wait
     if [ "$GW_STATE" != "available" ]; then
        echo "Waiting for existing NAT Gateway $NAT_GATEWAY_ID to become available..."
        aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GATEWAY_ID --region $AWS_REGION
        if [ $? -ne 0 ]; then echo "NAT Gateway $NAT_GATEWAY_ID failed to become available."; exit 1; fi
        echo "NAT Gateway $NAT_GATEWAY_ID is available."
     fi
fi
# --- End NAT Gateway ---

# --- Check/Create Public Route Table ---
# ... (Existing check/create logic, associate PUBLIC subnets, add route to IGW) ...

# --- Check/Create Private Subnet 1 (eu-west-1a) ---
# ... (Existing check/create logic) ...
# --- Check/Create Private Subnet 2 (eu-west-1b) ---
# ... (Existing check/create logic) ...

# --- Check/Create Private Route Table ---
PRIVATE_ROUTE_TABLE_NAME="${APP_NAME}-private-rtb"
echo "Checking/Creating Private Route Table: $PRIVATE_ROUTE_TABLE_NAME..."
PRIVATE_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters Name=tag:Name,Values=$PRIVATE_ROUTE_TABLE_NAME Name=vpc-id,Values=$VPC_ID --query 'RouteTables[0].RouteTableId' --output text --region $AWS_REGION 2>/dev/null)
if [ -z "$PRIVATE_ROUTE_TABLE_ID" ] || [ "$PRIVATE_ROUTE_TABLE_ID" == "None" ]; then
    echo "Private Route Table not found. Creating..."
    PRIVATE_ROUTE_TABLE_ID=$(aws ec2 create-route-table \
      --vpc-id $VPC_ID \
      --query 'RouteTable.RouteTableId' \
      --output text \
      --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$PRIVATE_ROUTE_TABLE_NAME},{Key=AppName,Value=$APP_NAME}]" \
      --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$PRIVATE_ROUTE_TABLE_ID" ]; then echo "Failed to create Private Route Table"; exit 1; fi
    echo "Created Private Route Table: $PRIVATE_ROUTE_TABLE_ID"
    NEEDS_NAT_ROUTE=true # Flag that we need to add the NAT route
else
    echo "Found existing Private Route Table: $PRIVATE_ROUTE_TABLE_ID"
    NEEDS_NAT_ROUTE=false # Assume route might exist, will check below
fi

# --- NEW: Associate Private Subnets with Private Route Table ---
echo "Associating Private Subnet 1 ($PRIVATE_SUBNET_1_ID) with Private Route Table ($PRIVATE_ROUTE_TABLE_ID)..."
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_1_ID --route-table-id $PRIVATE_ROUTE_TABLE_ID --region $AWS_REGION || echo "WARN: Failed to associate Private Subnet 1 (may already be associated)"
echo "Associating Private Subnet 2 ($PRIVATE_SUBNET_2_ID) with Private Route Table ($PRIVATE_ROUTE_TABLE_ID)..."
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_2_ID --route-table-id $PRIVATE_ROUTE_TABLE_ID --region $AWS_REGION || echo "WARN: Failed to associate Private Subnet 2 (may already be associated)"

# --- NEW: Add route to NAT Gateway in Private Route Table ---
echo "Checking/Creating route to NAT Gateway ($NAT_GATEWAY_ID) in Private Route Table ($PRIVATE_ROUTE_TABLE_ID)..."
# Check if the route already exists
ROUTE_EXISTS=$(aws ec2 describe-route-tables --route-table-ids $PRIVATE_ROUTE_TABLE_ID --filters Name=route.destination-cidr-block,Values='0.0.0.0/0' Name=route.nat-gateway-id,Values=$NAT_GATEWAY_ID --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0` && NatGatewayId==`'$NAT_GATEWAY_ID'`]' --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$ROUTE_EXISTS" ]; then
    echo "Route to NAT Gateway not found. Creating..."
    aws ec2 create-route \
      --route-table-id $PRIVATE_ROUTE_TABLE_ID \
      --destination-cidr-block 0.0.0.0/0 \
      --nat-gateway-id $NAT_GATEWAY_ID \
      --region $AWS_REGION
    if [ $? -ne 0 ]; then echo "Failed to create route to NAT Gateway in Private Route Table"; exit 1; fi
    echo "Created route 0.0.0.0/0 -> $NAT_GATEWAY_ID in $PRIVATE_ROUTE_TABLE_ID"
else
    echo "Route 0.0.0.0/0 -> $NAT_GATEWAY_ID already exists in $PRIVATE_ROUTE_TABLE_ID"
fi
# --- End Private Route Table ---

# Save VPC configuration
# ... (Existing save logic) ...

echo "VPC setup script completed." 
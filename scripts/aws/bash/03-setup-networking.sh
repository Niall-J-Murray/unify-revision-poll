#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"
mkdir -p "$CONFIG_DIR" # Ensure config directory exists

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"

echo "Setting up Networking (VPC, Subnets, Routes, Endpoints)..."

# --- VPC, IGW, Route Tables, Subnets, NAT Gateway ---

echo "Checking/Creating VPC resources..."
# Check/Create VPC
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
  local route_table_id=$4 # Optional: Route table to associate
  local __result_var=$5 # Variable name to store the result ID in the caller scope

  echo "Checking for subnet: $subnet_name in AZ $az..."
  local SUBNET_ID=$(aws ec2 describe-subnets \
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
        if [ $? -ne 0 ]; then echo "Failed to associate route table with $subnet_name"; exit 1; fi
    fi
  else
    echo "Found existing subnet $subnet_name: $SUBNET_ID"
  fi
  # Return the ID via indirect variable assignment
  if [[ "$__result_var" ]]; then
      eval $__result_var="'$SUBNET_ID'"
  else
      echo "$SUBNET_ID" # Fallback: print to stdout if no result var name given
  fi
}

# --- Create Subnets and Store IDs ---
check_create_subnet "${APP_NAME}-public-subnet-1" "$PUBLIC_SUBNET_1_CIDR" "${AWS_REGION}a" "$PUBLIC_RT_ID" PUBLIC_SUBNET_1_ID
check_create_subnet "${APP_NAME}-public-subnet-2" "$PUBLIC_SUBNET_2_CIDR" "${AWS_REGION}b" "$PUBLIC_RT_ID" PUBLIC_SUBNET_2_ID
check_create_subnet "${APP_NAME}-private-subnet-1" "$PRIVATE_SUBNET_1_CIDR" "${AWS_REGION}a" "" PRIVATE_SUBNET_1_ID # No RT needed here
check_create_subnet "${APP_NAME}-private-subnet-2" "$PRIVATE_SUBNET_2_CIDR" "${AWS_REGION}b" "" PRIVATE_SUBNET_2_ID # No RT needed here

# Export the subnet IDs to the current environment so subsequent steps in *this* script work
export PUBLIC_SUBNET_1_ID
export PUBLIC_SUBNET_2_ID
export PRIVATE_SUBNET_1_ID
export PRIVATE_SUBNET_2_ID

# --- Allocate Elastic IP for NAT Gateway ---
echo "Checking/Allocating Elastic IP for NAT Gateway..."
NAT_GW_CONFIG_FILE="$CONFIG_DIR/nat-gateway-config.sh"
if [ -f "$NAT_GW_CONFIG_FILE" ]; then
    source "$NAT_GW_CONFIG_FILE" # Loads EIP_ALLOCATION_ID, NAT_GATEWAY_ID
fi

EIP_EXISTS=false
if [ ! -z "$EIP_ALLOCATION_ID" ]; then
    EIP_ADDRESS=$(aws ec2 describe-addresses --allocation-ids $EIP_ALLOCATION_ID --query 'Addresses[0].PublicIp' --output text --region $AWS_REGION 2>/dev/null)
    if [ $? -eq 0 ] && [ ! -z "$EIP_ADDRESS" ]; then
        echo "Found existing Elastic IP: $EIP_ADDRESS (Allocation ID: $EIP_ALLOCATION_ID)"
        EIP_EXISTS=true
    else
        echo "Stored EIP Allocation ID $EIP_ALLOCATION_ID not found or invalid. Will allocate a new one."
        EIP_ALLOCATION_ID=""
    fi
fi

if [ "$EIP_EXISTS" = false ]; then
    echo "Allocating new Elastic IP..."
    ALLOCATION_RESULT=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$ALLOCATION_RESULT" ]; then echo "Failed to allocate Elastic IP"; exit 1; fi
    EIP_ALLOCATION_ID=$ALLOCATION_RESULT
    echo "Allocated Elastic IP with Allocation ID: $EIP_ALLOCATION_ID"
    # Save/Update the new ID - Overwrite the file robustly
    echo "#!/bin/bash" > "$NAT_GW_CONFIG_FILE"
    echo "# NAT Gateway Configuration" >> "$NAT_GW_CONFIG_FILE"
    echo "export EIP_ALLOCATION_ID=\\"$EIP_ALLOCATION_ID\\"" >> "$NAT_GW_CONFIG_FILE"
    # Add NAT_GATEWAY_ID placeholder if it existed before, otherwise it gets added later
    if [ -n "$NAT_GATEWAY_ID" ]; then
        echo "export NAT_GATEWAY_ID=\\"$NAT_GATEWAY_ID\\"" >> "$NAT_GW_CONFIG_FILE"
    fi
    chmod +x "$NAT_GW_CONFIG_FILE"
    echo "Updated $NAT_GW_CONFIG_FILE with new EIP Allocation ID."
fi

# --- Check/Create NAT Gateway in Public Subnet 1 ---
echo "Checking/Creating NAT Gateway..."
NAT_GATEWAY_ID_FOUND=""
if [ ! -z "$NAT_GATEWAY_ID" ]; then
    GW_STATE=$(aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_GATEWAY_ID --query 'NatGateways[0].State' --output text --region $AWS_REGION 2>/dev/null)
    if [ $? -eq 0 ] && [[ "$GW_STATE" != "deleted" && "$GW_STATE" != "failed" ]]; then
        echo "Found existing NAT Gateway: $NAT_GATEWAY_ID (State: $GW_STATE)"
        NAT_GATEWAY_ID_FOUND=$NAT_GATEWAY_ID
    else
        echo "Stored NAT Gateway ID $NAT_GATEWAY_ID not found or in unusable state. Will create a new one."
        NAT_GATEWAY_ID=""
    fi
fi

if [ -z "$NAT_GATEWAY_ID_FOUND" ]; then
    echo "Creating NAT Gateway in Public Subnet 1 ($PUBLIC_SUBNET_1_ID)..."
    CREATE_NAT_RESULT=$(aws ec2 create-nat-gateway \
      --subnet-id $PUBLIC_SUBNET_1_ID \
      --allocation-id $EIP_ALLOCATION_ID \
      --query 'NatGateway.NatGatewayId' \
      --output text \
      --tag-specifications "ResourceType=natgateway,Tags=[{Key=AppName,Value='$APP_NAME'},{Key=Name,Value='${APP_NAME}-nat-gw'}]" \
      --region $AWS_REGION)

    if [ $? -ne 0 ] || [ -z "$CREATE_NAT_RESULT" ]; then echo "Failed to create NAT Gateway"; exit 1; fi
    NAT_GATEWAY_ID=$CREATE_NAT_RESULT
    echo "Created NAT Gateway: $NAT_GATEWAY_ID. Waiting for it to become available..."

    # Save/Update the new ID - Overwrite the file robustly
    echo "#!/bin/bash" > "$NAT_GW_CONFIG_FILE"
    echo "# NAT Gateway Configuration" >> "$NAT_GW_CONFIG_FILE"
    echo "export EIP_ALLOCATION_ID=\\"$EIP_ALLOCATION_ID\\"" >> "$NAT_GW_CONFIG_FILE" # Keep existing EIP ID
    echo "export NAT_GATEWAY_ID=\\"$NAT_GATEWAY_ID\\"" >> "$NAT_GW_CONFIG_FILE" # Add the new NAT GW ID
    chmod +x "$NAT_GW_CONFIG_FILE"
    echo "Updated $NAT_GW_CONFIG_FILE with new NAT Gateway ID."

    aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GATEWAY_ID --region $AWS_REGION
    if [ $? -ne 0 ]; then echo "NAT Gateway $NAT_GATEWAY_ID failed to become available."; exit 1; fi
    echo "NAT Gateway $NAT_GATEWAY_ID is available."
else
     NAT_GATEWAY_ID=$NAT_GATEWAY_ID_FOUND
     # Ensure the config file reflects the found IDs even if no creation happened
     echo "#!/bin/bash" > "$NAT_GW_CONFIG_FILE"
     echo "# NAT Gateway Configuration" >> "$NAT_GW_CONFIG_FILE"
     echo "export EIP_ALLOCATION_ID=\\"$EIP_ALLOCATION_ID\\"" >> "$NAT_GW_CONFIG_FILE"
     echo "export NAT_GATEWAY_ID=\\"$NAT_GATEWAY_ID\\"" >> "$NAT_GW_CONFIG_FILE"
     chmod +x "$NAT_GW_CONFIG_FILE"
     if [ "$GW_STATE" != "available" ]; then
        echo "Waiting for existing NAT Gateway $NAT_GATEWAY_ID to become available..."
        aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GATEWAY_ID --region $AWS_REGION
        if [ $? -ne 0 ]; then echo "NAT Gateway $NAT_GATEWAY_ID failed to become available."; exit 1; fi
        echo "NAT Gateway $NAT_GATEWAY_ID is available."
     fi
fi

# --- Check/Create Private Route Table ---
PRIVATE_ROUTE_TABLE_NAME="${APP_NAME}-private-rt"
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
else
    echo "Found existing Private Route Table: $PRIVATE_ROUTE_TABLE_ID"
fi

# --- Associate Private Subnets with Private Route Table ---
echo "Associating Private Subnet 1 ($PRIVATE_SUBNET_1_ID) with Private Route Table ($PRIVATE_ROUTE_TABLE_ID)..."
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_1_ID --route-table-id $PRIVATE_ROUTE_TABLE_ID --region $AWS_REGION > /dev/null || echo "WARN: Failed to associate Private Subnet 1 (maybe already associated)"
echo "Associating Private Subnet 2 ($PRIVATE_SUBNET_2_ID) with Private Route Table ($PRIVATE_ROUTE_TABLE_ID)..."
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_2_ID --route-table-id $PRIVATE_ROUTE_TABLE_ID --region $AWS_REGION > /dev/null || echo "WARN: Failed to associate Private Subnet 2 (maybe already associated)"

# --- Add route to NAT Gateway in Private Route Table ---
echo "Checking/Creating route to NAT Gateway ($NAT_GATEWAY_ID) in Private Route Table ($PRIVATE_ROUTE_TABLE_ID)..."
ROUTE_EXISTS=$(aws ec2 describe-route-tables --route-table-ids $PRIVATE_ROUTE_TABLE_ID --filters Name=route.destination-cidr-block,Values='0.0.0.0/0' Name=route.nat-gateway-id,Values=$NAT_GATEWAY_ID --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0` && NatGatewayId==`'$NAT_GATEWAY_ID'`]' --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$ROUTE_EXISTS" ]; then
    echo "Route to NAT Gateway not found. Creating..."
    aws ec2 create-route \
      --route-table-id $PRIVATE_ROUTE_TABLE_ID \
      --destination-cidr-block 0.0.0.0/0 \
      --nat-gateway-id $NAT_GATEWAY_ID \
      --region $AWS_REGION
    if [ $? -ne 0 ]; then echo "Failed to create route to NAT Gateway"; exit 1; fi
else
    echo "Route to NAT Gateway already exists."
fi

# --- Check/Create Default Security Group (allowing essential traffic) ---
VPC_SECURITY_GROUP_NAME="${APP_NAME}-default-sg"
echo "Checking/Creating Default Security Group: $VPC_SECURITY_GROUP_NAME..."
VPC_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values="$VPC_SECURITY_GROUP_NAME" Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$VPC_SECURITY_GROUP_ID" ] || [ "$VPC_SECURITY_GROUP_ID" == "None" ]; then
    echo "Default Security Group not found. Creating..."
    VPC_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
      --group-name "$VPC_SECURITY_GROUP_NAME" \
      --description "Default security group for ${APP_NAME} allowing internal and essential outbound traffic" \
      --vpc-id $VPC_ID \
      --query 'GroupId' \
      --output text \
      --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$VPC_SECURITY_GROUP_ID" ]; then echo "Failed to create Default Security Group"; exit 1; fi
    aws ec2 create-tags --resources $VPC_SECURITY_GROUP_ID --tags Key=Name,Value="$VPC_SECURITY_GROUP_NAME" --region $AWS_REGION
    echo "Created Default Security Group: $VPC_SECURITY_GROUP_ID"

    # Allow all traffic within the VPC by default (adjust if needed for stricter rules)
    echo "Authorizing ingress within the VPC security group..."
    aws ec2 authorize-security-group-ingress --group-id $VPC_SECURITY_GROUP_ID --protocol all --cidr $VPC_CIDR --region $AWS_REGION || echo "WARN: Could not authorize self-ingress (might already exist)"

    # Allow all outbound traffic (essential for NAT Gateway and endpoints)
    # Note: Default SG usually allows all outbound. Explicitly ensuring it.
    echo "Ensuring all outbound traffic is allowed..."
    aws ec2 authorize-security-group-egress --group-id $VPC_SECURITY_GROUP_ID --protocol all --port all --cidr 0.0.0.0/0 --region $AWS_REGION || echo "WARN: Could not authorize all egress (might already exist)"

else
    echo "Found existing Default Security Group: $VPC_SECURITY_GROUP_ID"
fi

# --- Write VPC configuration File ---
VPC_CONFIG_FILE="$CONFIG_DIR/vpc-config.sh"
echo "Writing VPC configuration to $VPC_CONFIG_FILE..."
cat > "$VPC_CONFIG_FILE" << EOF
#!/bin/bash
# VPC Configuration - Generated by 03-setup-networking.sh

export VPC_ID="$VPC_ID"
export PUBLIC_SUBNET_1_ID="$PUBLIC_SUBNET_1_ID"
export PUBLIC_SUBNET_2_ID="$PUBLIC_SUBNET_2_ID"
export PRIVATE_SUBNET_1_ID="$PRIVATE_SUBNET_1_ID"
export PRIVATE_SUBNET_2_ID="$PRIVATE_SUBNET_2_ID"
export PRIVATE_ROUTE_TABLE_ID="$PRIVATE_ROUTE_TABLE_ID"
export VPC_SECURITY_GROUP_ID="$VPC_SECURITY_GROUP_ID"
# Note: Public Route Table ID ($PUBLIC_RT_ID) and IGW ID ($IGW_ID) are generally not needed by subsequent scripts.

EOF
chmod +x "$VPC_CONFIG_FILE"
echo "VPC configuration saved."

# --- VPC Endpoints ---
echo "Checking/Creating VPC endpoints..."

# Function to check/create an interface endpoint
check_create_interface_endpoint() {
  local service_name_suffix=$1 # e.g., ssm, ecr.api
  local endpoint_name="${APP_NAME}-${service_name_suffix//./-}-endpoint" # e.g., feature-poll-ssm-endpoint

  echo "Checking for VPC endpoint: $service_name_suffix ($endpoint_name)..."
  ENDPOINT_ID=$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC_ID Name=service-name,Values="com.amazonaws.${AWS_REGION}.${service_name_suffix}" Name=tag:Name,Values="$endpoint_name" --query 'VpcEndpoints[?State==`available`].VpcEndpointId' --output text --region $AWS_REGION 2>/dev/null)

  if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" == "None" ]; then
    echo "Endpoint for $service_name_suffix not found or not available. Creating..."
    ENDPOINT_ID=$(aws ec2 create-vpc-endpoint \
        --vpc-id $VPC_ID \
        --service-name "com.amazonaws.${AWS_REGION}.${service_name_suffix}" \
        --vpc-endpoint-type Interface \
        --subnet-ids $PRIVATE_SUBNET_1_ID $PRIVATE_SUBNET_2_ID \
        --security-group-ids $VPC_SECURITY_GROUP_ID \
        --private-dns-enabled \
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$endpoint_name},{Key=AppName,Value=$APP_NAME}]" \
        --query 'VpcEndpoint.VpcEndpointId' \
        --output text \
        --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$ENDPOINT_ID" ]; then echo "Failed to create endpoint for $service_name_suffix"; exit 1; fi
    echo "Created endpoint for $service_name_suffix: $ENDPOINT_ID. Waiting for it to become available..."
    
    # --- FIX: Replace invalid wait command with polling loop ---
    MAX_WAIT_TIME=300 # 5 minutes
    INTERVAL=15 # Check every 15 seconds
    elapsed_time=0
    while [ $elapsed_time -lt $MAX_WAIT_TIME ]; do
        ENDPOINT_STATE=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $ENDPOINT_ID --query "VpcEndpoints[0].State" --output text --region $AWS_REGION 2>/dev/null)
        if [ "$ENDPOINT_STATE" == "available" ]; then
            echo "Endpoint $ENDPOINT_ID is available."
            break
        elif [[ "$ENDPOINT_STATE" == "pending" ]]; then
            echo "   ...still pending (State: $ENDPOINT_STATE)"
        else
            echo "Error: Endpoint $ENDPOINT_ID entered unexpected state: $ENDPOINT_STATE"
            exit 1
        fi
        sleep $INTERVAL
        elapsed_time=$((elapsed_time + INTERVAL))
    done

    if [ $elapsed_time -ge $MAX_WAIT_TIME ]; then
        echo "Error: Timeout waiting for endpoint $ENDPOINT_ID to become available."
        exit 1
    fi
    # --- END FIX ---

  else
    # If endpoint exists, get details for confirmation (optional)
    ENDPOINT_DETAILS=$(aws ec2 describe-vpc-endpoints --vpc-endpoint-ids $ENDPOINT_ID --query "VpcEndpoints[0].{Subnets:SubnetIds, SGs:Groups[*].GroupId}" --output json --region $AWS_REGION 2>/dev/null)
    echo "Found existing available endpoint for $service_name_suffix: $ENDPOINT_ID Details: $ENDPOINT_DETAILS"
  fi
}

# Function to check/create a gateway endpoint (S3)
check_create_gateway_endpoint() {
  local service_name_suffix=$1 # e.g., s3
  local endpoint_name="${APP_NAME}-${service_name_suffix}-gateway-endpoint"

  echo "Checking for VPC gateway endpoint: $service_name_suffix ($endpoint_name)..."
  # Gateway endpoints don't have tags easily filterable, check based on service and VPC
  ENDPOINT_ID=$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=$VPC_ID Name=service-name,Values="com.amazonaws.${AWS_REGION}.${service_name_suffix}" --query 'VpcEndpoints[?VpcEndpointType==`Gateway` && State==`available`].VpcEndpointId' --output text --region $AWS_REGION 2>/dev/null)

  if [ -z "$ENDPOINT_ID" ] || [ "$ENDPOINT_ID" == "None" ]; then
    echo "Gateway endpoint for $service_name_suffix not found or not available. Creating..."
    ENDPOINT_ID=$(aws ec2 create-vpc-endpoint \
        --vpc-id $VPC_ID \
        --service-name "com.amazonaws.${AWS_REGION}.${service_name_suffix}" \
        --vpc-endpoint-type Gateway \
        --route-table-ids $PRIVATE_ROUTE_TABLE_ID \
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$endpoint_name},{Key=AppName,Value=$APP_NAME}]" \
        --query 'VpcEndpoint.VpcEndpointId' \
        --output text \
        --region $AWS_REGION)
     if [ $? -ne 0 ] || [ -z "$ENDPOINT_ID" ]; then echo "Failed to create gateway endpoint for $service_name_suffix"; exit 1; fi
     echo "Created gateway endpoint for $service_name_suffix: $ENDPOINT_ID"
     # Gateway endpoints are available almost immediately, no wait needed generally.
  else
    echo "Found existing available gateway endpoint for $service_name_suffix: $ENDPOINT_ID"
  fi
}

# Create required endpoints using the functions
check_create_interface_endpoint "ssm"
check_create_interface_endpoint "ssmmessages"
check_create_interface_endpoint "ecr.api"
check_create_interface_endpoint "ecr.dkr"
check_create_interface_endpoint "logs"
check_create_gateway_endpoint "s3"

echo "VPC Endpoints checked/created successfully."
echo "Networking setup complete." 
#!/bin/bash

# This script sets up a Bastion Host for secure SSH access to private resources.

echo "Setting up Bastion Host..."

# --- Configuration (EDIT THESE) ---
# Replace with the name of the EC2 Key Pair you created in the AWS Console (eu-west-1)
# Make sure you have the corresponding .pem file saved locally.
BASTION_KEY_PAIR_NAME="feature-poll-bastion-key"

# Replace with YOUR current public IPv4 address, followed by /32
# Example: "81.100.99.55/32"
# Find your IP by searching "what is my ip address" on Google.
YOUR_PUBLIC_IP_CIDR="37.228.206.27/32"

# --- End Configuration ---

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"
# Config files should exist from previous step, no need to mkdir -p here

# Source primary variables
if [ -f "$SCRIPT_DIR/01-setup-variables.sh" ]; then
    source "$SCRIPT_DIR/01-setup-variables.sh"
else
    echo "Error: 01-setup-variables.sh not found."
    exit 1
fi

# Source VPC and RDS configs (needed for VPC ID, Public Subnet, RDS SG ID)
if [ -f "$CONFIG_DIR/vpc-config.sh" ]; then
    source "$CONFIG_DIR/vpc-config.sh"
else
    echo "Error: vpc-config.sh not found in $CONFIG_DIR. Run 03-setup-networking.sh first."
    exit 1
fi
if [ -f "$CONFIG_DIR/rds-config.sh" ]; then
    source "$CONFIG_DIR/rds-config.sh" # Loads SECURITY_GROUP_ID as DB_SG_ID
    DB_SG_ID=$SECURITY_GROUP_ID
else
    echo "Error: rds-config.sh not found in $CONFIG_DIR. Run 04-create-rds.sh first."
    exit 1
fi

# --- Validate Configuration ---
# Check against generic placeholders instead of specific examples
if [ "$BASTION_KEY_PAIR_NAME" == "YOUR_KEY_PAIR_NAME" ] || [ -z "$BASTION_KEY_PAIR_NAME" ]; then
    echo "Error: Please edit this script and set the BASTION_KEY_PAIR_NAME variable (it cannot be empty or 'YOUR_KEY_PAIR_NAME')."
    exit 1
fi
if [ "$YOUR_PUBLIC_IP_CIDR" == "YOUR_IP_ADDRESS/32" ] || [ -z "$YOUR_PUBLIC_IP_CIDR" ]; then
    echo "Error: Please edit this script and set the YOUR_PUBLIC_IP_CIDR variable (it cannot be empty or 'YOUR_IP_ADDRESS/32')."
    exit 1
fi
if ! [[ "$YOUR_PUBLIC_IP_CIDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/32$ ]]; then
    echo "Error: YOUR_PUBLIC_IP_CIDR format looks incorrect. Should be like '1.2.3.4/32'."
    exit 1
fi


# --- Allocate Elastic IP for Bastion --- 
echo "Checking/Allocating Elastic IP for Bastion Host..."
BASTION_CONFIG_FILE="$CONFIG_DIR/bastion-config.sh"
BASTION_EIP_ALLOCATION_ID=""
BASTION_EIP_ADDRESS=""
EIP_FOUND_METHOD=""

# Check 1: Try loading from config file
echo "   Checking config file: $BASTION_CONFIG_FILE..."
if [ -f "$BASTION_CONFIG_FILE" ]; then
    source "$BASTION_CONFIG_FILE" # Loads BASTION_EIP_ALLOCATION_ID, BASTION_EIP_ADDRESS
    if [ -n "$BASTION_EIP_ALLOCATION_ID" ]; then
        echo "      Found Allocation ID in config: $BASTION_EIP_ALLOCATION_ID. Verifying..."
        DESCRIBED_ADDRESS_INFO=$(aws ec2 describe-addresses --allocation-ids $BASTION_EIP_ALLOCATION_ID --query 'Addresses[0]' --output json --region $AWS_REGION 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$DESCRIBED_ADDRESS_INFO" ] && [ "$DESCRIBED_ADDRESS_INFO" != "null" ]; then
            # EIP exists, extract details
            BASTION_EIP_ADDRESS=$(echo "$DESCRIBED_ADDRESS_INFO" | jq -r '.PublicIp')
            echo "      Verified existing Bastion Elastic IP via config: $BASTION_EIP_ADDRESS (Allocation ID: $BASTION_EIP_ALLOCATION_ID)"
            EIP_FOUND_METHOD="config"
        else
            echo "      Stored Bastion EIP Allocation ID $BASTION_EIP_ALLOCATION_ID not found or invalid in AWS."
            BASTION_EIP_ALLOCATION_ID=""
            BASTION_EIP_ADDRESS=""
        fi
    else
         echo "      Config file exists but BASTION_EIP_ALLOCATION_ID not set."
    fi
else
     echo "      Config file not found."
fi

# Check 2: Try finding an unassociated VPC EIP if not found via config
if [ -z "$EIP_FOUND_METHOD" ]; then
    echo "   Attempting to find an existing unassociated VPC Elastic IP..."
    # Query for VPC EIPs with no AssociationId, get the first one's AllocId and PublicIp
    UNASSOCIATED_EIP_INFO=$(aws ec2 describe-addresses \
        --filters Name=domain,Values=vpc \
        --query 'Addresses[?AssociationId==null]|[0].[AllocationId, PublicIp]' \
        --output text --region $AWS_REGION 2>/dev/null)
    
    if [ -n "$UNASSOCIATED_EIP_INFO" ] && [ "$UNASSOCIATED_EIP_INFO" != "None" ]; then
        # Found one, extract details
        BASTION_EIP_ALLOCATION_ID=$(echo $UNASSOCIATED_EIP_INFO | cut -d' ' -f1)
        BASTION_EIP_ADDRESS=$(echo $UNASSOCIATED_EIP_INFO | cut -d' ' -f2)
        echo "      Found and reusing unassociated EIP: $BASTION_EIP_ADDRESS (Allocation ID: $BASTION_EIP_ALLOCATION_ID)"
        EIP_FOUND_METHOD="reuse_unassociated"
    else
        echo "      No suitable unassociated VPC EIP found."
    fi
fi

# Step 3: Allocate a new EIP if not found via config or reuse
if [ -z "$EIP_FOUND_METHOD" ]; then
    echo "   Allocating a new Elastic IP for Bastion..."
    # Add tags during allocation
    TAG_SPECS="ResourceType=elastic-ip,Tags=[{Key=AppName,Value='$APP_NAME'},{Key=Role,Value=BastionEIP}]"
    ALLOCATION_RESULT=$(aws ec2 allocate-address --domain vpc --tag-specifications "$TAG_SPECS" --query '[AllocationId, PublicIp]' --output text --region $AWS_REGION)
    
    ALLOCATION_EXIT_CODE=$?
    if [ $ALLOCATION_EXIT_CODE -ne 0 ] || [ -z "$ALLOCATION_RESULT" ] || [ "$ALLOCATION_RESULT" == "None" ]; then 
        echo "      Error: Failed to allocate new Elastic IP for Bastion."
        # Check specifically for AddressLimitExceeded
        if aws ec2 allocate-address --domain vpc --tag-specifications "$TAG_SPECS" --region $AWS_REGION 2>&1 | grep -q 'AddressLimitExceeded'; then
             echo "      Reason: AddressLimitExceeded - The maximum number of Elastic IPs for your account in $AWS_REGION has been reached."
             echo "      Please release unused Elastic IPs in the AWS EC2 console or request a service quota increase."
        fi
        exit 1; 
    fi
    
    BASTION_EIP_ALLOCATION_ID=$(echo $ALLOCATION_RESULT | cut -d' ' -f1)
    BASTION_EIP_ADDRESS=$(echo $ALLOCATION_RESULT | cut -d' ' -f2)
    echo "      Allocated new Bastion Elastic IP: $BASTION_EIP_ADDRESS (Allocation ID: $BASTION_EIP_ALLOCATION_ID)"
    EIP_FOUND_METHOD="allocated_new"
fi

# Step 4: Save the configuration regardless of how the EIP was obtained (if method is known)
if [ -n "$EIP_FOUND_METHOD" ]; then
    echo "   Saving EIP details to $BASTION_CONFIG_FILE..."
    echo "#!/bin/bash" > "$BASTION_CONFIG_FILE"
    echo "# Bastion Host Configuration (EIP)" >> "$BASTION_CONFIG_FILE"
    echo "export BASTION_EIP_ALLOCATION_ID=\"$BASTION_EIP_ALLOCATION_ID\"" >> "$BASTION_CONFIG_FILE"
    echo "export BASTION_EIP_ADDRESS=\"$BASTION_EIP_ADDRESS\"" >> "$BASTION_CONFIG_FILE"
    chmod +x "$BASTION_CONFIG_FILE"
else
    # Should not happen if logic above is correct, but safeguard
    echo "Error: Could not determine Bastion EIP Allocation ID or Address after all checks. Exiting."
    exit 1
fi

# --- Check/Create Bastion Security Group ---
BASTION_SG_NAME="${APP_NAME}-bastion-sg"
echo "Checking/Creating Bastion Security Group: $BASTION_SG_NAME..."
BASTION_SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=$BASTION_SG_NAME Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$BASTION_SG_ID" ] || [ "$BASTION_SG_ID" == "None" ]; then
  echo "Bastion Security Group not found. Creating..."
  BASTION_SG_ID=$(aws ec2 create-security-group \
    --group-name $BASTION_SG_NAME \
    --description "Security group for ${APP_NAME} Bastion Host" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=AppName,Value='$APP_NAME'},{Key=Role,Value=Bastion}]" \
    --region $AWS_REGION)
  if [ $? -ne 0 ] || [ -z "$BASTION_SG_ID" ]; then echo "Failed to create Bastion Security Group"; exit 1; fi
  echo "Created Bastion security group: $BASTION_SG_ID"

  # Authorize SSH ONLY from the specified IP CIDR when creating
  echo "Authorizing SSH ingress from $YOUR_PUBLIC_IP_CIDR to Bastion SG $BASTION_SG_ID..."
  aws ec2 authorize-security-group-ingress --group-id $BASTION_SG_ID --protocol tcp --port 22 --cidr $YOUR_PUBLIC_IP_CIDR --region $AWS_REGION
  if [ $? -ne 0 ]; then echo "Failed to add SSH ingress rule to Bastion SG"; exit 1; fi
  echo "SSH ingress rule added."
else
  echo "Found existing Bastion security group: $BASTION_SG_ID"
  echo "INFO: Ensure SSH ingress rule for $YOUR_PUBLIC_IP_CIDR exists. Manual update might be needed if your IP changed."
  # Optional TODO: Add logic here to check/update the ingress rule if IP changed.
fi

# --- Check/Create EC2 Instance (Bastion Host) ---
echo "Checking/Creating Bastion EC2 Instance..."
BASTION_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:AppName,Values=$APP_NAME" "Name=tag:Role,Values=Bastion" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$BASTION_INSTANCE_ID" ] || [ "$BASTION_INSTANCE_ID" == "None" ]; then
    echo "Bastion instance not found. Launching..."
    # Find latest Amazon Linux 2023 AMI
    echo "Finding latest Amazon Linux 2023 AMI..."
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters 'Name=name,Values=al2023-ami-2023.*-kernel-*-x86_64' 'Name=state,Values=available' 'Name=architecture,Values=x86_64' \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text --region $AWS_REGION)
    if [ $? -ne 0 ] || [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
        echo "Error: Could not find latest Amazon Linux 2023 AMI."
        exit 1
    fi
    echo "Using AMI ID: $AMI_ID"

    # Define instance type
    INSTANCE_TYPE=$BASTION_INSTANCE_TYPE # Use variable from 01-setup-variables.sh
    echo "Using instance type: $INSTANCE_TYPE"

    # Launch the EC2 instance
    echo "Launching $INSTANCE_TYPE instance in Public Subnet 1 ($PUBLIC_SUBNET_1_ID)..."
    RUN_RESULT=$(aws ec2 run-instances \
        --image-id $AMI_ID \
        --instance-type $INSTANCE_TYPE \
        --key-name "$BASTION_KEY_PAIR_NAME" \
        --security-group-ids $BASTION_SG_ID \
        --subnet-id $PUBLIC_SUBNET_1_ID \
        --no-associate-public-ip-address \
        --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":8,"VolumeType":"gp3"}}]' \
        --tag-specifications "ResourceType=instance,Tags=[{Key=AppName,Value=$APP_NAME},{Key=Name,Value=${APP_NAME}-bastion},{Key=Role,Value=Bastion}]" "ResourceType=volume,Tags=[{Key=AppName,Value=$APP_NAME},{Key=Name,Value=${APP_NAME}-bastion-volume}]" \
        --query 'Instances[0].InstanceId' \
        --output text \
        --region $AWS_REGION)

    if [ $? -ne 0 ] || [ -z "$RUN_RESULT" ]; then echo "Failed to launch Bastion instance"; exit 1; fi
    BASTION_INSTANCE_ID=$RUN_RESULT
    echo "Launched Bastion instance: $BASTION_INSTANCE_ID. Waiting for it to enter 'running' state..."

    aws ec2 wait instance-running --instance-ids $BASTION_INSTANCE_ID --region $AWS_REGION
    if [ $? -ne 0 ]; then echo "Error: Wait failed. Bastion instance $BASTION_INSTANCE_ID did not enter running state."; exit 1; fi
    echo "Bastion instance is running."

    # Associate the Elastic IP
    echo "Associating Elastic IP $BASTION_EIP_ADDRESS with instance $BASTION_INSTANCE_ID..."
    aws ec2 associate-address --instance-id $BASTION_INSTANCE_ID --allocation-id $BASTION_EIP_ALLOCATION_ID --region $AWS_REGION
    if [ $? -ne 0 ]; then echo "Failed to associate Elastic IP with Bastion instance"; exit 1; fi
    echo "Elastic IP associated."
else
    echo "Found existing Bastion instance: $BASTION_INSTANCE_ID"
    # Ensure EIP is associated if instance exists but EIP was just re-allocated
    CURRENT_ASSOCIATION=$(aws ec2 describe-addresses --allocation-ids $BASTION_EIP_ALLOCATION_ID --query 'Addresses[0].AssociationId' --output text --region $AWS_REGION 2>/dev/null)
    if [ -z "$CURRENT_ASSOCIATION" ] || [ "$CURRENT_ASSOCIATION" == "None" ]; then
         echo "Associating Elastic IP $BASTION_EIP_ADDRESS with existing instance $BASTION_INSTANCE_ID..."
         aws ec2 associate-address --instance-id $BASTION_INSTANCE_ID --allocation-id $BASTION_EIP_ALLOCATION_ID --region $AWS_REGION || echo "WARN: Failed to associate Elastic IP with existing Bastion instance."
    fi
fi

# --- Update RDS Security Group --- 
echo "Updating RDS Security Group ($DB_SG_ID) to allow ingress from Bastion SG ($BASTION_SG_ID)..."

echo "Attempting to add ingress rule to RDS SG (duplicate rule errors will be ignored)..."
# Execute command, redirecting stderr to stdout to capture it
ERROR_OUTPUT=$(aws ec2 authorize-security-group-ingress \
    --group-id $DB_SG_ID \
    --protocol tcp \
    --port 5432 \
    --source-group $BASTION_SG_ID \
    --region $AWS_REGION 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    # Check if the error is the specific duplicate rule error
    if echo "$ERROR_OUTPUT" | grep -q "InvalidPermission.Duplicate"; then
        echo "INFO: Ingress rule from Bastion SG to RDS SG already exists."
    else
        # A different error occurred
        echo "Error: Failed to add ingress rule from Bastion to RDS SG:"
        echo "$ERROR_OUTPUT"
        exit 1
    fi
else
    # Command succeeded (rule was added)
    echo "RDS SG ingress rule added successfully."
fi

# --- Output Connection Info --- 
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "${APP_NAME}-db" --query 'DBInstances[0].Endpoint.Address' --output text --region $AWS_REGION)

echo ""
echo "-----------------------------------------------------"
echo "Bastion Host Setup Complete!"
echo ""
echo "Bastion Public IP: $BASTION_EIP_ADDRESS"
echo "Bastion Instance ID: $BASTION_INSTANCE_ID"
echo "Key Pair Name: $BASTION_KEY_PAIR_NAME"
echo "RDS Endpoint: $RDS_ENDPOINT"
echo ""
echo "To connect to your RDS database via the Bastion Host:"
echo "1. Make sure your '$BASTION_KEY_PAIR_NAME.pem' file has correct permissions (chmod 400 /path/to/$BASTION_KEY_PAIR_NAME.pem)"
echo "2. Open a NEW local terminal and run the following SSH command:"
echo "   ssh -i /path/to/$BASTION_KEY_PAIR_NAME.pem ec2-user@$BASTION_EIP_ADDRESS -L 5432:$RDS_ENDPOINT:5432 -N"
# Note: Use al2023 default username 'ec2-user'. Use 'ubuntu' for Ubuntu AMIs, etc.
echo "   (Replace '/path/to/$BASTION_KEY_PAIR_NAME.pem' with the actual path to your key file)"
echo "   (The '-N' flag prevents executing remote commands - good for just tunneling)"
echo "3. Keep that SSH terminal running."
echo "4. In ANOTHER local terminal or your database client, connect to PostgreSQL using:"
echo "   Host: localhost"
echo "   Port: 5432"
echo "   Database: $DB_NAME"
echo "   Username: $DB_USERNAME"
echo "   Password: [The password generated or set in 01-setup-variables.sh]"
echo "-----------------------------------------------------"

echo "Bastion setup script finished." 
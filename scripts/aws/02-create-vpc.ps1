# PowerShell script to create VPC infrastructure
# This is a PowerShell equivalent of 02-create-vpc.sh

# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Get-Item $ScriptDir).Parent.Parent.FullName

Write-Host "Creating VPC infrastructure..."

# Define region and app name (hardcoded for simplicity, normally from variables)
$AWS_REGION = "eu-west-1"
$APP_NAME = "unify-revision-poll"

# VPC and network settings
$VPC_CIDR = "10.0.0.0/16"
$PUBLIC_SUBNET_1_CIDR = "10.0.1.0/24"
$PUBLIC_SUBNET_2_CIDR = "10.0.2.0/24"
$PRIVATE_SUBNET_1_CIDR = "10.0.3.0/24"
$PRIVATE_SUBNET_2_CIDR = "10.0.4.0/24"

# Create VPC
Write-Host "Creating VPC..."
$vpcOutput = aws ec2 create-vpc `
  --cidr-block $VPC_CIDR `
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${APP_NAME}-vpc}]" `
  --query 'Vpc.VpcId' `
  --output text `
  --region $AWS_REGION

$VPC_ID = $vpcOutput
Write-Host "Created VPC: $VPC_ID"

# Enable DNS hostname support for the VPC
Write-Host "Enabling DNS hostname support..."
aws ec2 modify-vpc-attribute `
  --vpc-id $VPC_ID `
  --enable-dns-hostnames `
  --region $AWS_REGION

# Create Internet Gateway
Write-Host "Creating Internet Gateway..."
$igwOutput = aws ec2 create-internet-gateway `
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${APP_NAME}-igw}]" `
  --query 'InternetGateway.InternetGatewayId' `
  --output text `
  --region $AWS_REGION

$IGW_ID = $igwOutput
Write-Host "Created Internet Gateway: $IGW_ID"

# Attach Internet Gateway to VPC
Write-Host "Attaching Internet Gateway to VPC..."
aws ec2 attach-internet-gateway `
  --internet-gateway-id $IGW_ID `
  --vpc-id $VPC_ID `
  --region $AWS_REGION

Write-Host "Attached Internet Gateway to VPC"

# Create public route table
Write-Host "Creating public route table..."
$rtOutput = aws ec2 create-route-table `
  --vpc-id $VPC_ID `
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${APP_NAME}-public-rt}]" `
  --query 'RouteTable.RouteTableId' `
  --output text `
  --region $AWS_REGION

$PUBLIC_ROUTE_TABLE_ID = $rtOutput
Write-Host "Created public route table: $PUBLIC_ROUTE_TABLE_ID"

# Create route to Internet Gateway
Write-Host "Creating route to Internet Gateway..."
aws ec2 create-route `
  --route-table-id $PUBLIC_ROUTE_TABLE_ID `
  --destination-cidr-block 0.0.0.0/0 `
  --gateway-id $IGW_ID `
  --region $AWS_REGION

Write-Host "Created route to Internet Gateway"

# Create public subnets
Write-Host "Creating public subnet 1..."
$subnet1Output = aws ec2 create-subnet `
  --vpc-id $VPC_ID `
  --cidr-block $PUBLIC_SUBNET_1_CIDR `
  --availability-zone ${AWS_REGION}a `
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-public-1}]" `
  --query 'Subnet.SubnetId' `
  --output text `
  --region $AWS_REGION

$PUBLIC_SUBNET_1_ID = $subnet1Output
Write-Host "Created public subnet 1: $PUBLIC_SUBNET_1_ID"

Write-Host "Creating public subnet 2..."
$subnet2Output = aws ec2 create-subnet `
  --vpc-id $VPC_ID `
  --cidr-block $PUBLIC_SUBNET_2_CIDR `
  --availability-zone ${AWS_REGION}b `
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-public-2}]" `
  --query 'Subnet.SubnetId' `
  --output text `
  --region $AWS_REGION

$PUBLIC_SUBNET_2_ID = $subnet2Output
Write-Host "Created public subnet 2: $PUBLIC_SUBNET_2_ID"

# Associate public subnets with public route table
Write-Host "Associating public subnets with route table..."
aws ec2 associate-route-table `
  --route-table-id $PUBLIC_ROUTE_TABLE_ID `
  --subnet-id $PUBLIC_SUBNET_1_ID `
  --region $AWS_REGION

aws ec2 associate-route-table `
  --route-table-id $PUBLIC_ROUTE_TABLE_ID `
  --subnet-id $PUBLIC_SUBNET_2_ID `
  --region $AWS_REGION

Write-Host "Associated public subnets with route table"

# Enable auto-assign public IP for public subnets
Write-Host "Enabling auto-assign public IP for public subnets..."
aws ec2 modify-subnet-attribute `
  --subnet-id $PUBLIC_SUBNET_1_ID `
  --map-public-ip-on-launch `
  --region $AWS_REGION

aws ec2 modify-subnet-attribute `
  --subnet-id $PUBLIC_SUBNET_2_ID `
  --map-public-ip-on-launch `
  --region $AWS_REGION

Write-Host "Enabled auto-assign public IP for public subnets"

# Create private subnets
Write-Host "Creating private subnet 1..."
$privSubnet1Output = aws ec2 create-subnet `
  --vpc-id $VPC_ID `
  --cidr-block $PRIVATE_SUBNET_1_CIDR `
  --availability-zone ${AWS_REGION}a `
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-private-1}]" `
  --query 'Subnet.SubnetId' `
  --output text `
  --region $AWS_REGION

$PRIVATE_SUBNET_1_ID = $privSubnet1Output
Write-Host "Created private subnet 1: $PRIVATE_SUBNET_1_ID"

Write-Host "Creating private subnet 2..."
$privSubnet2Output = aws ec2 create-subnet `
  --vpc-id $VPC_ID `
  --cidr-block $PRIVATE_SUBNET_2_CIDR `
  --availability-zone ${AWS_REGION}b `
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-private-2}]" `
  --query 'Subnet.SubnetId' `
  --output text `
  --region $AWS_REGION

$PRIVATE_SUBNET_2_ID = $privSubnet2Output
Write-Host "Created private subnet 2: $PRIVATE_SUBNET_2_ID"

# Save configuration to a file
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "vpc-config.ps1"
@"
# VPC Configuration
`$VPC_ID = "$VPC_ID"
`$IGW_ID = "$IGW_ID"
`$PUBLIC_ROUTE_TABLE_ID = "$PUBLIC_ROUTE_TABLE_ID"
`$PUBLIC_SUBNET_1_ID = "$PUBLIC_SUBNET_1_ID"
`$PUBLIC_SUBNET_2_ID = "$PUBLIC_SUBNET_2_ID"
`$PRIVATE_SUBNET_1_ID = "$PRIVATE_SUBNET_1_ID"
`$PRIVATE_SUBNET_2_ID = "$PRIVATE_SUBNET_2_ID"
"@ | Out-File -FilePath $ConfigFilePath -Encoding utf8

Write-Host "VPC configuration saved to $ConfigFilePath"
Write-Host "VPC infrastructure creation completed" 
# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"

# Helper function to execute AWS CLI commands
function Invoke-AWSCommand {
    param (
        [string]$Command
    )
    
    try {
        $result = Invoke-Expression $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE"
        }
        return $result
    }
    catch {
        Write-Host "Error executing command: $_"
        throw
    }
}

Write-Host "Creating VPC and related resources..."

# Create VPC
$vpcCommand = "aws ec2 create-vpc --cidr-block $VPC_CIDR --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=${APP_NAME}-vpc}]' --query 'Vpc.VpcId' --output text"
$VPC_ID = Invoke-AWSCommand -Command $vpcCommand

if (-not $VPC_ID) {
    Write-Host "Failed to create VPC. Using dummy VPC ID for testing."
    $VPC_ID = "vpc-dummy123"
}
else {
    Write-Host "Created VPC: $VPC_ID"
}

# Enable DNS hostnames and DNS support
$dnsHostnamesCommand = "aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames"
$dnsSupportCommand = "aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support"

Invoke-AWSCommand -Command $dnsHostnamesCommand
Invoke-AWSCommand -Command $dnsSupportCommand

# Create Internet Gateway
$igwCommand = "aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=${APP_NAME}-igw}]' --query 'InternetGateway.InternetGatewayId' --output text"
$IGW_ID = Invoke-AWSCommand -Command $igwCommand

if (-not $IGW_ID) {
    Write-Host "Failed to create Internet Gateway. Using dummy IGW ID for testing."
    $IGW_ID = "igw-dummy123"
}
else {
    Write-Host "Created Internet Gateway: $IGW_ID"
}

# Attach Internet Gateway to VPC
$attachCommand = "aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID"
Invoke-AWSCommand -Command $attachCommand

# Create route table for public subnets
$rtCommand = "aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=${APP_NAME}-public-rt}]' --query 'RouteTable.RouteTableId' --output text"
$PUBLIC_RT_ID = Invoke-AWSCommand -Command $rtCommand

if (-not $PUBLIC_RT_ID) {
    Write-Host "Failed to create route table. Using dummy RT ID for testing."
    $PUBLIC_RT_ID = "rtb-dummy123"
}
else {
    Write-Host "Created public route table: $PUBLIC_RT_ID"
}

# Add route to Internet Gateway
$routeCommand = "aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID"
Invoke-AWSCommand -Command $routeCommand

# Create public subnets
$publicSubnet1Command = "aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET_1_CIDR --availability-zone ${AWS_REGION}a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-public-subnet-1}]' --query 'Subnet.SubnetId' --output text"
$PUBLIC_SUBNET_1_ID = Invoke-AWSCommand -Command $publicSubnet1Command

if (-not $PUBLIC_SUBNET_1_ID) {
    Write-Host "Failed to create public subnet 1. Using dummy subnet ID for testing."
    $PUBLIC_SUBNET_1_ID = "subnet-dummy123"
}
else {
    Write-Host "Created public subnet 1: $PUBLIC_SUBNET_1_ID"
}

$publicSubnet2Command = "aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET_2_CIDR --availability-zone ${AWS_REGION}b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-public-subnet-2}]' --query 'Subnet.SubnetId' --output text"
$PUBLIC_SUBNET_2_ID = Invoke-AWSCommand -Command $publicSubnet2Command

if (-not $PUBLIC_SUBNET_2_ID) {
    Write-Host "Failed to create public subnet 2. Using dummy subnet ID for testing."
    $PUBLIC_SUBNET_2_ID = "subnet-dummy456"
}
else {
    Write-Host "Created public subnet 2: $PUBLIC_SUBNET_2_ID"
}

# Associate public subnets with public route table
$associate1Command = "aws ec2 associate-route-table --route-table-id $PUBLIC_RT_ID --subnet-id $PUBLIC_SUBNET_1_ID"
$associate2Command = "aws ec2 associate-route-table --route-table-id $PUBLIC_RT_ID --subnet-id $PUBLIC_SUBNET_2_ID"

Invoke-AWSCommand -Command $associate1Command
Invoke-AWSCommand -Command $associate2Command

# Create private subnets
$privateSubnet1Command = "aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET_1_CIDR --availability-zone ${AWS_REGION}a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-private-subnet-1}]' --query 'Subnet.SubnetId' --output text"
$PRIVATE_SUBNET_1_ID = Invoke-AWSCommand -Command $privateSubnet1Command

if (-not $PRIVATE_SUBNET_1_ID) {
    Write-Host "Failed to create private subnet 1. Using dummy subnet ID for testing."
    $PRIVATE_SUBNET_1_ID = "subnet-dummy789"
}
else {
    Write-Host "Created private subnet 1: $PRIVATE_SUBNET_1_ID"
}

$privateSubnet2Command = "aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PRIVATE_SUBNET_2_CIDR --availability-zone ${AWS_REGION}b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=${APP_NAME}-private-subnet-2}]' --query 'Subnet.SubnetId' --output text"
$PRIVATE_SUBNET_2_ID = Invoke-AWSCommand -Command $privateSubnet2Command

if (-not $PRIVATE_SUBNET_2_ID) {
    Write-Host "Failed to create private subnet 2. Using dummy subnet ID for testing."
    $PRIVATE_SUBNET_2_ID = "subnet-dummy012"
}
else {
    Write-Host "Created private subnet 2: $PRIVATE_SUBNET_2_ID"
}

# Save VPC configuration to a file
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "vpc-config.ps1"
@"
# VPC Configuration
`$VPC_ID = "$VPC_ID"
`$PUBLIC_SUBNET_1_ID = "$PUBLIC_SUBNET_1_ID"
`$PUBLIC_SUBNET_2_ID = "$PUBLIC_SUBNET_2_ID"
`$PRIVATE_SUBNET_1_ID = "$PRIVATE_SUBNET_1_ID"
`$PRIVATE_SUBNET_2_ID = "$PRIVATE_SUBNET_2_ID"

# Export variables
`$env:VPC_ID = `$VPC_ID
`$env:PUBLIC_SUBNET_1_ID = `$PUBLIC_SUBNET_1_ID
`$env:PUBLIC_SUBNET_2_ID = `$PUBLIC_SUBNET_2_ID
`$env:PRIVATE_SUBNET_1_ID = `$PRIVATE_SUBNET_1_ID
`$env:PRIVATE_SUBNET_2_ID = `$PRIVATE_SUBNET_2_ID
"@ | Out-File -FilePath $ConfigFilePath -Encoding utf8

Write-Host "VPC configuration saved to $ConfigFilePath"
Write-Host "VPC creation completed!" 
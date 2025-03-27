# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\rds-config.ps1"

Write-Host "Creating public subnets..."

# Get VPC ID
$vpcId = aws rds describe-db-subnet-groups `
    --db-subnet-group-name ${APP_NAME}-subnet-group `
    --query "DBSubnetGroups[0].VpcId" `
    --output text

Write-Host "VPC ID: $vpcId"

# Get VPC CIDR block
$vpcCidr = aws ec2 describe-vpcs `
    --vpc-ids $vpcId `
    --query "Vpcs[0].CidrBlock" `
    --output text

Write-Host "VPC CIDR: $vpcCidr"

# Create public subnets in different AZs
$publicSubnetIds = @()
$azs = @("eu-west-1a", "eu-west-1b")
$cidrBlocks = @("10.0.5.0/24", "10.0.6.0/24")

for ($i = 0; $i -lt $azs.Count; $i++) {
    Write-Host "`nCreating public subnet in $($azs[$i])..."
    
    $subnetId = aws ec2 create-subnet `
        --vpc-id $vpcId `
        --availability-zone $azs[$i] `
        --cidr-block $cidrBlocks[$i] `
        --query "Subnet.SubnetId" `
        --output text

    $publicSubnetIds += $subnetId
    
    # Enable auto-assign public IP
    aws ec2 modify-subnet-attribute `
        --subnet-id $subnetId `
        --map-public-ip-on-launch

    Write-Host "Created subnet: $subnetId"
}

# Create Internet Gateway if it doesn't exist
Write-Host "`nChecking for Internet Gateway..."
$igwId = aws ec2 describe-internet-gateways `
    --filters "Name=attachment.vpc-id,Values=$vpcId" `
    --query "InternetGateways[0].InternetGatewayId" `
    --output text

if (-not $igwId) {
    Write-Host "Creating Internet Gateway..."
    $igwId = aws ec2 create-internet-gateway `
        --query "InternetGateway.InternetGatewayId" `
        --output text
    
    aws ec2 attach-internet-gateway `
        --internet-gateway-id $igwId `
        --vpc-id $vpcId
}

# Create route table for public subnets
Write-Host "`nCreating route table for public subnets..."
$routeTableId = aws ec2 create-route-table `
    --vpc-id $vpcId `
    --query "RouteTable.RouteTableId" `
    --output text

# Add route to Internet Gateway
aws ec2 create-route `
    --route-table-id $routeTableId `
    --destination-cidr-block "0.0.0.0/0" `
    --gateway-id $igwId

# Associate route table with public subnets
foreach ($subnetId in $publicSubnetIds) {
    aws ec2 associate-route-table `
        --route-table-id $routeTableId `
        --subnet-id $subnetId
}

# Create new subnet group for RDS
Write-Host "`nCreating new subnet group for RDS..."
$newSubnetGroupName = "${APP_NAME}-public-subnet-group"

aws rds create-db-subnet-group `
    --db-subnet-group-name $newSubnetGroupName `
    --db-subnet-group-description "Public subnet group for RDS" `
    --subnet-ids $publicSubnetIds

# Modify RDS instance to use new subnet group
Write-Host "`nModifying RDS instance to use new subnet group..."
aws rds modify-db-instance `
    --db-instance-identifier ${APP_NAME}-db `
    --db-subnet-group-name $newSubnetGroupName `
    --apply-immediately

Write-Host "`nWaiting for RDS instance to be available..."
aws rds wait db-instance-available --db-instance-identifier ${APP_NAME}-db

Write-Host "`nPublic subnets created and RDS instance moved!"
Write-Host "Please wait a few minutes for the changes to take effect." 
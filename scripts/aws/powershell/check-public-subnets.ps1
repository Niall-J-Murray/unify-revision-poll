# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\rds-config.ps1"

Write-Host "Checking for public subnets..."

# Get VPC ID
$vpcId = aws rds describe-db-subnet-groups `
    --db-subnet-group-name ${APP_NAME}-subnet-group `
    --query "DBSubnetGroups[0].VpcId" `
    --output text

Write-Host "VPC ID: $vpcId"

# Get all subnets in the VPC
Write-Host "`nAll subnets in VPC:"
$subnets = aws ec2 describe-subnets `
    --filters "Name=vpc-id,Values=$vpcId" `
    --query "Subnets[*]" `
    --output json

$subnets | ConvertFrom-Json | ForEach-Object {
    Write-Host "`nSubnet ID: $($_.SubnetId)"
    Write-Host "Availability Zone: $($_.AvailabilityZone)"
    Write-Host "CIDR Block: $($_.CidrBlock)"
    Write-Host "Map Public IP on Launch: $($_.MapPublicIpOnLaunch)"
    Write-Host "----------------------------------------"
}

# Get public subnets specifically
Write-Host "`nPublic subnets only:"
$publicSubnets = aws ec2 describe-subnets `
    --filters "Name=vpc-id,Values=$vpcId" "Name=map-public-ip-on-launch,Values=true" `
    --query "Subnets[*]" `
    --output json

$publicSubnets | ConvertFrom-Json | ForEach-Object {
    Write-Host "`nSubnet ID: $($_.SubnetId)"
    Write-Host "Availability Zone: $($_.AvailabilityZone)"
    Write-Host "CIDR Block: $($_.CidrBlock)"
    Write-Host "----------------------------------------"
} 
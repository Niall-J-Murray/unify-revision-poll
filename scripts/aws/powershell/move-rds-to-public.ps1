# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\rds-config.ps1"

Write-Host "Moving RDS instance to public subnets..."

# Get VPC ID
$vpcId = aws rds describe-db-subnet-groups `
    --db-subnet-group-name ${APP_NAME}-subnet-group `
    --query "DBSubnetGroups[0].VpcId" `
    --output text

Write-Host "VPC ID: $vpcId"

# Get public subnets
$publicSubnets = aws ec2 describe-subnets `
    --filters "Name=vpc-id,Values=$vpcId" "Name=map-public-ip-on-launch,Values=true" `
    --query "Subnets[*].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,CidrBlock:CidrBlock}" `
    --output table

Write-Host "`nAvailable public subnets:"
$publicSubnets

# Create new subnet group with public subnets
$newSubnetGroupName = "${APP_NAME}-public-subnet-group"
Write-Host "`nCreating new subnet group: $newSubnetGroupName"

$subnetIds = $publicSubnets | ConvertFrom-Json | Select-Object -ExpandProperty SubnetId

aws rds create-db-subnet-group `
    --db-subnet-group-name $newSubnetGroupName `
    --db-subnet-group-description "Public subnet group for RDS" `
    --subnet-ids $subnetIds

# Modify RDS instance to use new subnet group
Write-Host "`nModifying RDS instance to use new subnet group..."
aws rds modify-db-instance `
    --db-instance-identifier ${APP_NAME}-db `
    --db-subnet-group-name $newSubnetGroupName `
    --apply-immediately

Write-Host "`nWaiting for RDS instance to be available..."
aws rds wait db-instance-available --db-instance-identifier ${APP_NAME}-db

Write-Host "`nRDS instance has been moved to public subnets!"
Write-Host "Please wait a few minutes for the changes to take effect." 
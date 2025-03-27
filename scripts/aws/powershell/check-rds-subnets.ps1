# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\rds-config.ps1"

Write-Host "Checking RDS subnet configuration..."

# Get RDS instance details
$rdsDetails = aws rds describe-db-instances `
    --db-instance-identifier ${APP_NAME}-db `
    --query "DBInstances[0].{PubliclyAccessible:PubliclyAccessible,VpcSecurityGroups:VpcSecurityGroups[*].VpcSecurityGroupId,DBSubnetGroup:DBSubnetGroup.DBSubnetGroupName}" `
    --output table

Write-Host "`nRDS Instance Details:"
$rdsDetails

# Get subnet group details
$subnetGroup = aws rds describe-db-subnet-groups `
    --db-subnet-group-name ${APP_NAME}-subnet-group `
    --query "DBSubnetGroups[0]" `
    --output json

Write-Host "`nSubnet Group Details:"
$subnetGroup | ConvertFrom-Json | ConvertTo-Json

# Get subnet details
$subnetIds = $subnetGroup | ConvertFrom-Json | Select-Object -ExpandProperty Subnets | Select-Object -ExpandProperty SubnetIdentifier

Write-Host "`nSubnet Details:"
foreach ($subnetId in $subnetIds) {
    Write-Host "`nSubnet ID: ${subnetId}"
    $subnetInfo = aws ec2 describe-subnets `
        --subnet-ids $subnetId `
        --query "Subnets[0].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch,CidrBlock:CidrBlock}" `
        --output table
    
    $subnetInfo
} 
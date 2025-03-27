# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\rds-config.ps1"

Write-Host "Checking RDS instance settings..."

# Get RDS instance details
$rdsDetails = aws rds describe-db-instances `
    --db-instance-identifier ${APP_NAME}-db `
    --query "DBInstances[0].{PubliclyAccessible:PubliclyAccessible,VpcSecurityGroups:VpcSecurityGroups[*].VpcSecurityGroupId,DBSubnetGroup:DBSubnetGroup.DBSubnetGroupName}" `
    --output table

Write-Host "`nRDS Instance Details:"
$rdsDetails

# Get VPC details
$vpcId = aws rds describe-db-subnet-groups `
    --db-subnet-group-name ${APP_NAME}-subnet-group `
    --query "DBSubnetGroups[0].VpcId" `
    --output text

Write-Host "`nVPC ID: $vpcId"

# Get subnet details
$subnetDetails = aws rds describe-db-subnet-groups `
    --db-subnet-group-name ${APP_NAME}-subnet-group `
    --query "DBSubnetGroups[0].Subnets[*].{SubnetId:SubnetIdentifier,AvailabilityZone:SubnetAvailabilityZone}" `
    --output table

Write-Host "`nSubnet Details:"
$subnetDetails 
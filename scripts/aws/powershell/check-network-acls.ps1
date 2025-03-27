# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\rds-config.ps1"

Write-Host "Checking Network ACLs..."

# Get VPC ID from subnet group
$vpcId = aws rds describe-db-subnet-groups `
    --db-subnet-group-name ${APP_NAME}-subnet-group `
    --query "DBSubnetGroups[0].VpcId" `
    --output text

Write-Host "VPC ID: $vpcId"

# Get Network ACLs associated with the VPC
Write-Host "`nNetwork ACLs:"
aws ec2 describe-network-acls `
    --filters "Name=vpc-id,Values=$vpcId" `
    --query "NetworkAcls[*].{NetworkAclId:NetworkAclId,Entries:Entries[*].{RuleNumber:RuleNumber,Protocol:Protocol,RuleAction:RuleAction,Egress:Egress,CidrBlock:CidrBlock,PortRange:PortRange}}" `
    --output table

# Get route tables
Write-Host "`nRoute Tables:"
aws ec2 describe-route-tables `
    --filters "Name=vpc-id,Values=$vpcId" `
    --query "RouteTables[*].{RouteTableId:RouteTableId,Routes:Routes[*].{DestinationCidrBlock:DestinationCidrBlock,State:State}}" `
    --output table 
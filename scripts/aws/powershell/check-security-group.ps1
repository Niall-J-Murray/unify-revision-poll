# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\rds-config.ps1"

# Get current IP address
$MyIP = Invoke-RestMethod -Uri "https://api.ipify.org/"
$MyIPWithCIDR = "$MyIP/32"

Write-Host "Current IP: $MyIPWithCIDR"
Write-Host "Security Group ID: $SECURITY_GROUP_ID"

# Check current security group rules
Write-Host "`nCurrent security group rules:"
aws ec2 describe-security-groups `
    --group-ids $SECURITY_GROUP_ID `
    --query "SecurityGroups[0].IpPermissions" `
    --output table

# Add new inbound rule for PostgreSQL
Write-Host "`nAdding new inbound rule for PostgreSQL..."
aws ec2 authorize-security-group-ingress `
    --group-id $SECURITY_GROUP_ID `
    --protocol tcp `
    --port 5432 `
    --cidr $MyIPWithCIDR

Write-Host "`nUpdated security group rules:"
aws ec2 describe-security-groups `
    --group-ids $SECURITY_GROUP_ID `
    --query "SecurityGroups[0].IpPermissions" `
    --output table 
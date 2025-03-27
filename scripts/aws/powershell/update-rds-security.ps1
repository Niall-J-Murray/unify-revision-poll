# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\rds-config.ps1"

# Get current IP address
$MyIP = Invoke-RestMethod -Uri "https://api.ipify.org/"
$MyIPWithCIDR = "$MyIP/32"

Write-Host "Adding inbound rule for IP: $MyIPWithCIDR"

try {
    # Add inbound rule for PostgreSQL
    aws ec2 authorize-security-group-ingress `
        --group-id $SECURITY_GROUP_ID `
        --protocol tcp `
        --port 5432 `
        --cidr $MyIPWithCIDR

    Write-Host "Security group updated successfully!"
} catch {
    if ($_.Exception.Message -like "*InvalidPermission.Duplicate*") {
        Write-Host "Security group rule already exists. This is fine."
    } else {
        Write-Host "Error updating security group: $_"
        exit 1
    }
}
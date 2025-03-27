# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\rds-config.ps1"

Write-Host "Making RDS instance publicly accessible..."

# Modify RDS instance to be publicly accessible
Write-Host "Modifying RDS instance..."
aws rds modify-db-instance `
    --db-instance-identifier ${APP_NAME}-db `
    --publicly-accessible `
    --apply-immediately

Write-Host "`nWaiting for RDS instance to be available..."
aws rds wait db-instance-available --db-instance-identifier ${APP_NAME}-db

# Get the new endpoint
$newEndpoint = aws rds describe-db-instances `
    --db-instance-identifier ${APP_NAME}-db `
    --query "DBInstances[0].Endpoint.Address" `
    --output text

Write-Host "`nRDS instance is now publicly accessible!"
Write-Host "New endpoint: $newEndpoint"
Write-Host "Please wait a few minutes for the changes to take effect." 
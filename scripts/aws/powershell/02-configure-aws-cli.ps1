# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"

Write-Host "Configuring AWS CLI..."

# Check if AWS CLI is installed
try {
    $null = Get-Command aws -ErrorAction Stop
}
catch {
    Write-Host "AWS CLI is not installed. Please install it first."
    exit 1
}

# Check if AWS credentials are set
if (-not $env:AWS_ACCESS_KEY_ID -or -not $env:AWS_SECRET_ACCESS_KEY) {
    Write-Host "AWS credentials not found. Please set the following environment variables:"
    Write-Host "AWS_ACCESS_KEY_ID"
    Write-Host "AWS_SECRET_ACCESS_KEY"
    Write-Host "You can set them using:"
    Write-Host '$env:AWS_ACCESS_KEY_ID = "your-access-key"'
    Write-Host '$env:AWS_SECRET_ACCESS_KEY = "your-secret-key"'
    exit 1
}

# Configure AWS CLI
aws configure set aws_access_key_id $env:AWS_ACCESS_KEY_ID
aws configure set aws_secret_access_key $env:AWS_SECRET_ACCESS_KEY
aws configure set default.region $AWS_REGION
aws configure set default.output json

Write-Host "AWS CLI configuration completed!" 
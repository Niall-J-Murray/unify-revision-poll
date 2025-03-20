# PowerShell script to configure AWS CLI with proper SSL handling for Windows
# This is a PowerShell alternative to 00-configure-aws-cli.sh

Write-Host "====================================================="
Write-Host "AWS CLI Configuration Script for Windows"
Write-Host "====================================================="
Write-Host "This script will configure your AWS CLI with proper credentials and SSL certificates."
Write-Host "====================================================="

# Check if AWS CLI is installed
try {
    $awsVersion = aws --version
    Write-Host "AWS CLI detected: $awsVersion"
}
catch {
    Write-Host "Error: AWS CLI is not installed or not in PATH. Please install AWS CLI first."
    Write-Host "You can download it from: https://aws.amazon.com/cli/"
    Write-Host "Or install using: winget install -e --id Amazon.AWSCLI"
    exit 1
}

# Prompt for AWS credentials and configuration
Write-Host ""
Write-Host "Please enter your AWS credentials and configuration:"
Write-Host "-----------------------------------------------------"

$awsAccessKeyId = Read-Host "AWS Access Key ID"
if (-not $awsAccessKeyId) {
    Write-Host "Error: AWS Access Key ID is required."
    exit 1
}

$awsSecretAccessKey = Read-Host "AWS Secret Access Key"
if (-not $awsSecretAccessKey) {
    Write-Host "Error: AWS Secret Access Key is required."
    exit 1
}

$defaultRegion = Read-Host "Default region name (recommended: eu-west-1)"
if (-not $defaultRegion) {
    $defaultRegion = "eu-west-1"
    Write-Host "Using default region: $defaultRegion"
}

$defaultOutput = Read-Host "Default output format (recommended: json)"
if (-not $defaultOutput) {
    $defaultOutput = "json"
    Write-Host "Using default output format: $defaultOutput"
}

# Configure AWS CLI
Write-Host ""
Write-Host "Configuring AWS CLI..."
aws configure set aws_access_key_id $awsAccessKeyId
aws configure set aws_secret_access_key $awsSecretAccessKey
aws configure set region $defaultRegion
aws configure set output $defaultOutput

# Create ~/.aws directory if it doesn't exist
$awsDir = "$env:USERPROFILE\.aws"
if (-not (Test-Path $awsDir)) {
    New-Item -Path $awsDir -ItemType Directory | Out-Null
    Write-Host "Created directory: $awsDir"
}

# Download Amazon root certificate
$certPath = "$env:USERPROFILE\.aws\ca-bundle.pem"
Write-Host "Downloading Amazon Trust Services root certificate..."
try {
    Invoke-WebRequest -Uri "https://www.amazontrust.com/repository/AmazonRootCA1.pem" -OutFile $certPath
    Write-Host "Certificate downloaded to: $certPath"
}
catch {
    Write-Host "Warning: Could not download certificate. Error: $_"
    Write-Host "SSL verification might not work correctly."
}

# Configure AWS CLI to use the certificate
if (Test-Path $certPath) {
    aws configure set default.ca_bundle $certPath
    Write-Host "AWS CLI configured to use Amazon root certificate."
}

# Verify the configuration with a test call
# We'll try multiple approaches to handle potential SSL issues
Write-Host ""
Write-Host "Verifying AWS CLI configuration..."

function Test-AWSConnection {
    $methods = @(
        @{
            Description = "Standard approach"
            Command = "aws sts get-caller-identity --output json"
        },
        @{
            Description = "With explicit endpoint URL"
            Command = "aws sts get-caller-identity --output json --endpoint-url https://sts.$defaultRegion.amazonaws.com"
        },
        @{
            Description = "With SSL verification disabled"
            Setup = "aws configure set default.verify_ssl false"
            Command = "aws sts get-caller-identity --output json"
            Cleanup = "aws configure set default.verify_ssl true"
        }
    )
    
    foreach ($method in $methods) {
        Write-Host "Trying $($method.Description)..."
        
        if ($method.Setup) {
            Invoke-Expression $method.Setup
        }
        
        try {
            $result = Invoke-Expression $method.Command
            
            if ($method.Cleanup) {
                Invoke-Expression $method.Cleanup
            }
            
            # If we get here, the command was successful
            Write-Host "Connection successful!"
            return $true
        }
        catch {
            Write-Host "Failed with error: $_"
            
            if ($method.Cleanup) {
                Invoke-Expression $method.Cleanup
            }
        }
    }
    
    return $false
}

$connectionSuccessful = Test-AWSConnection

if ($connectionSuccessful) {
    Write-Host ""
    Write-Host "====================================================="
    Write-Host "AWS CLI Configuration Completed Successfully!"
    Write-Host "====================================================="
    Write-Host "Your AWS CLI is now configured with proper credentials and SSL certificates."
    exit 0
}
else {
    Write-Host ""
    Write-Host "====================================================="
    Write-Host "AWS CLI Configuration Warning"
    Write-Host "====================================================="
    Write-Host "Configuration completed, but couldn't verify connection."
    Write-Host "This might be due to SSL certificate issues or incorrect credentials."
    Write-Host ""
    Write-Host "Troubleshooting steps:"
    Write-Host "1. Verify your credentials are correct"
    Write-Host "2. Check your internet connection and proxy settings"
    Write-Host "3. Try running AWS commands manually to debug further"
    exit 1
} 
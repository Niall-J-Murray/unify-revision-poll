# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"

# Helper function to execute AWS CLI commands
function Invoke-AWSCommand {
    param (
        [string]$Command,
        [switch]$IgnoreErrors = $false
    )
    
    try {
        $result = Invoke-Expression $Command
        if ($LASTEXITCODE -ne 0) {
            if ($IgnoreErrors) {
                return $null
            }
            throw "Command failed with exit code $LASTEXITCODE"
        }
        return $result
    }
    catch {
        if ($IgnoreErrors) {
            Write-Host "Warning: $($_.Exception.Message)"
            return $null
        }
        Write-Host "Error executing command: $_"
        throw
    }
}

Write-Host "Creating ECR repository..."

# Check if repository exists
$checkCommand = "aws ecr describe-repositories --repository-names $ECR_REPOSITORY_NAME --query 'repositories[0].repositoryName' --output text"
$REPOSITORY_EXISTS = Invoke-AWSCommand -Command $checkCommand -IgnoreErrors

if (-not $REPOSITORY_EXISTS) {
    # Create repository
    $createCommand = "aws ecr create-repository --repository-name $ECR_REPOSITORY_NAME --image-scanning-configuration scanOnPush=true --image-tag-mutability MUTABLE"
    Invoke-AWSCommand -Command $createCommand
    Write-Host "Created ECR repository: $ECR_REPOSITORY_NAME"
}
else {
    Write-Host "Repository already exists: $ECR_REPOSITORY_NAME"
}

# Get repository URI
$uriCommand = "aws ecr describe-repositories --repository-names $ECR_REPOSITORY_NAME --query 'repositories[0].repositoryUri' --output text"
$REPOSITORY_URI = Invoke-AWSCommand -Command $uriCommand

if (-not $REPOSITORY_URI) {
    Write-Host "Failed to get repository URI. Using dummy URI for testing."
    $REPOSITORY_URI = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY_NAME}"
}
else {
    Write-Host "Repository URI: $REPOSITORY_URI"
}

# Save ECR configuration to a file
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "ecr-config.ps1"
@"
# ECR Configuration
`$REPOSITORY_URI = "$REPOSITORY_URI"

# Export variables
`$env:REPOSITORY_URI = `$REPOSITORY_URI
"@ | Out-File -FilePath $ConfigFilePath -Encoding utf8

Write-Host "ECR configuration saved to $ConfigFilePath"
Write-Host "ECR repository creation completed!" 
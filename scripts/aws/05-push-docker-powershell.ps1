# PowerShell script to build and push Docker image to ECR with Windows compatibility options
# This is a PowerShell alternative to 05-push-docker.sh

# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Get-Item $ScriptDir).Parent.Parent.FullName

Write-Host "Building and pushing Docker image to ECR (Windows-optimized version)..."

# Define region and app name (hardcoded for simplicity, normally from variables)
$AWS_REGION = "eu-west-1"
$APP_NAME = "unify-revision-poll"

# Load ECR configuration
$EcrConfigFile = Join-Path -Path $ScriptDir -ChildPath "ecr-config.ps1"
if (Test-Path $EcrConfigFile) {
    . $EcrConfigFile
}
else {
    Write-Host "Error: ECR configuration file not found at $EcrConfigFile"
    Write-Host "Please run the ECR creation script first."
    exit 1
}

# Define a function to run AWS commands with error handling
# This function tries multiple approaches to work around Windows-specific SSL issues
function Invoke-AWSCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command
    )
    
    Write-Host "Running AWS command: $Command"
    
    # Method 1: Standard approach with our certificate bundle
    try {
        $result = Invoke-Expression $Command
        return $result
    }
    catch {
        Write-Host "Standard approach failed, trying with endpoint URL..."
    }
    
    # Method 2: Try with endpoint URL
    $endpointCommand = $Command
    if ($Command -match "aws ecr") {
        $endpointCommand = $Command -replace "aws ecr", "aws ecr --endpoint-url=https://ecr.$AWS_REGION.amazonaws.com"
    }
    
    try {
        $result = Invoke-Expression $endpointCommand
        return $result
    }
    catch {
        Write-Host "Endpoint approach failed, trying with SSL verification disabled..."
    }
    
    # Method 3: Temporarily disable SSL verification as a last resort
    aws configure set default.verify_ssl false
    try {
        $result = Invoke-Expression $Command
        aws configure set default.verify_ssl true  # Re-enable SSL verification
        return $result
    }
    catch {
        Write-Host "All methods failed. Error: $_"
        Write-Host "Please check your AWS credentials and network connection."
        aws configure set default.verify_ssl true  # Re-enable SSL verification
        return $null
    }
}

# Check if Docker is installed
try {
    $dockerVersion = docker --version
    Write-Host "Docker detected: $dockerVersion"
}
catch {
    Write-Host "Error: Docker is not installed or not in PATH. Please install Docker first."
    exit 1
}

# Get ECR login password and login to Docker
Write-Host "Logging in to ECR..."
$pwdCommand = "aws ecr get-login-password --region $AWS_REGION"
$password = Invoke-AWSCommand -Command $pwdCommand

if ($password) {
    Write-Host "Logging in to Docker with AWS credentials..."
    try {
        # Use a temporary file to avoid PowerShell pipe handling issues
        $tempFile = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tempFile -Value $password -NoNewline
        $loginResult = cmd /c "type $tempFile | docker login --username AWS --password-stdin $ECR_REPO_URI"
        Remove-Item -Path $tempFile -Force
        
        Write-Host "Successfully logged in to ECR with Docker"
    }
    catch {
        Write-Host "Failed to login to Docker. Please check if Docker is installed and running."
        Write-Host "Error: $_"
        exit 1
    }
}
else {
    Write-Host "Could not get ECR login password. Exiting."
    exit 1
}

# Build Docker image
Write-Host "Building Docker image..."
Set-Location -Path $ProjectRoot

try {
    docker build -t $APP_NAME .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Docker build failed"
        exit 1
    }
    Write-Host "Docker image built successfully"
}
catch {
    Write-Host "Error during Docker build: $_"
    exit 1
}

# Tag Docker image
Write-Host "Tagging Docker image..."
try {
    docker tag $APP_NAME $ECR_REPO_URI
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Docker tag failed"
        exit 1
    }
    Write-Host "Docker image tagged successfully"
}
catch {
    Write-Host "Error during Docker tag: $_"
    exit 1
}

# Push Docker image to ECR
Write-Host "Pushing Docker image to ECR..."
try {
    docker push $ECR_REPO_URI
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Docker push failed"
        exit 1
    }
    Write-Host "Docker image pushed successfully to $ECR_REPO_URI"
}
catch {
    Write-Host "Error during Docker push: $_"
    exit 1
}

# Save Docker image URI to a file
$ImageConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "docker-image-config.ps1"
@"
# Docker Image Configuration
`$DOCKER_IMAGE_URI = "$ECR_REPO_URI"
"@ | Out-File -FilePath $ImageConfigFilePath -Encoding utf8

Write-Host "Docker image URI saved to $ImageConfigFilePath"
Write-Host "Docker image build and push completed!" 
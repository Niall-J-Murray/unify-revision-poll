# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Get-Item $ScriptDir).Parent.Parent.Parent.FullName

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\ecr-config.ps1"

Write-Host "Building and pushing Docker image..."

# Build the Docker image
Write-Host "Building Docker image from $ProjectRoot"
$buildCommand = "docker build -t $ECR_REPOSITORY_NAME`:latest -f `"$ProjectRoot\Dockerfile`" `"$ProjectRoot`""
Invoke-Expression $buildCommand

# Tag the image
$tagCommand = "docker tag $ECR_REPOSITORY_NAME`:latest $REPOSITORY_URI`:latest"
Invoke-Expression $tagCommand

# Get ECR login token and login to Docker
$loginCommand = "aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REPOSITORY_URI"
Invoke-Expression $loginCommand

# Push the image to ECR
$pushCommand = "docker push $REPOSITORY_URI`:latest"
Invoke-Expression $pushCommand

Write-Host "Docker image pushed successfully!" 
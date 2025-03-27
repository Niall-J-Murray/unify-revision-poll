# ... (Load environment variables, Invoke-AWSCommand function) ...
. "$PSScriptRoot\ecr-config.ps1" # Source ECR config

Write-Host "Building and pushing Docker image..."

# Get Project Root
$ProjectRoot = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath "../../..")).Path
Write-Host "Project Root: $ProjectRoot"

# Login to ECR
$ecrLoginCommand = "aws ecr get-login-password --region $($env:AWS_REGION) | docker login --username AWS --password-stdin $($env:REPOSITORY_URI)"
Invoke-Expression $ecrLoginCommand # Use Invoke-Expression to handle piping
if ($LASTEXITCODE -ne 0) { Write-Error "ECR login failed"; exit 1 }

# --- Change to Project Root Directory ---
Write-Host "Changing directory to $ProjectRoot"
try {
    Set-Location -Path $ProjectRoot -ErrorAction Stop
} catch {
    Write-Error "Failed to change directory to project root: $_"; exit 1
}

# Build the Docker image from the current directory (.)
Write-Host "Running docker build from context: $(Get-Location)"
$dockerBuildCommand = "docker build -t $($env:ECR_REPOSITORY_NAME):latest ."
Invoke-AWSCommand -Command $dockerBuildCommand
if ($LASTEXITCODE -ne 0) { Write-Error "Docker build failed"; exit 1 }

# --- Optional: Change back to original directory ---
# Set-Location -Path $PSScriptRoot

# Tag the image
$dockerTagCommand = "docker tag $($env:ECR_REPOSITORY_NAME):latest $($env:REPOSITORY_URI):latest"
Invoke-AWSCommand -Command $dockerTagCommand
if ($LASTEXITCODE -ne 0) { Write-Error "Docker tag failed"; exit 1 }

# Push the image to ECR
$dockerPushCommand = "docker push $($env:REPOSITORY_URI):latest"
Invoke-AWSCommand -Command $dockerPushCommand
if ($LASTEXITCODE -ne 0) { Write-Error "Docker push failed"; exit 1 }

Write-Host "Docker image pushed successfully!" 
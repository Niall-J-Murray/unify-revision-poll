# Main deployment script for the unify-revision-poll application

# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Get-Item $ScriptDir).Parent.Parent.FullName

Write-Host "Starting full AWS deployment for unify-revision-poll..."
Write-Host "This process will deploy the entire infrastructure and may take 30-60 minutes."

# Step 0: Configure AWS CLI
Write-Host "Step 0/10: Configuring AWS CLI"
& "$ScriptDir\00-configure-aws-cli-windows.ps1"

# Check if Git Bash is available for running bash scripts
$gitBashPath = "C:\Program Files\Git\bin\bash.exe"
$gitBashExists = Test-Path $gitBashPath

if (-not $gitBashExists) {
    Write-Host "Git Bash not found at $gitBashPath."
    Write-Host "You need Git Bash or WSL to run the bash deployment scripts."
    Write-Host "Please install Git for Windows from https://gitforwindows.org/ and run this script again."
    exit 1
}

Write-Host "Git Bash found. Will use it to run the deployment scripts."

# Function to run bash scripts with Git Bash
function Run-BashScript {
    param (
        [string]$ScriptPath
    )
    
    & "$gitBashPath" -c "cd '$ProjectRoot' && $ScriptPath"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Script $ScriptPath failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

# Step 1: Set up environment variables
Write-Host "Step 1/10: Setting up environment variables"
Run-BashScript "$ScriptDir/01-setup-variables.sh"

# Step 2: Create VPC, subnets, and Internet Gateway
Write-Host "Step 2/10: Creating VPC, subnets, and Internet Gateway"
Run-BashScript "$ScriptDir/02-create-vpc.sh"

# Step 3: Create RDS PostgreSQL database
Write-Host "Step 3/10: Creating RDS PostgreSQL database"
Run-BashScript "$ScriptDir/03-create-rds.sh"

# Step 4: Create ECR repository and push Docker image
Write-Host "Step 4/10: Creating ECR repository and pushing Docker image"
Run-BashScript "$ScriptDir/04-create-ecr-push-image.sh"

# Step 5: Create SSL certificate and initial Route 53 records
Write-Host "Step 5/10: Creating SSL certificate and initial Route 53 records"
Run-BashScript "$ScriptDir/05-create-ssl-certificate.sh"

# Step 6: Create secrets for environment variables
Write-Host "Step 6/10: Creating secrets for environment variables"
Run-BashScript "$ScriptDir/06-create-secrets.sh"

# Step 7: Create ECS resources (cluster, task definition, service)
Write-Host "Step 7/10: Creating ECS resources"
Run-BashScript "$ScriptDir/07-create-ecs-resources.sh"

# Step 8: Create Route 53 record for the domain
Write-Host "Step 8/10: Creating Route 53 records"
Run-BashScript "$ScriptDir/08-create-route53-record.sh"

# Step 9: Finalize deployment and show summary
Write-Host "Step 9/10: Finalizing deployment"
Run-BashScript "$ScriptDir/09-finalize-deployment.sh"

Write-Host "Full deployment process completed!"
Write-Host "Your application should be accessible at https://${env:SUBDOMAIN}.${env:DOMAIN_NAME} shortly."
Write-Host "Note that DNS propagation and certificate validation may take some time." 
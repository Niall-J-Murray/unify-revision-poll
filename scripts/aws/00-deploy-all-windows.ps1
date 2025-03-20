# Master deployment script for Windows
# This script orchestrates the entire deployment process on AWS from a Windows environment

# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Get-Item $ScriptDir).Parent.Parent.FullName

Write-Host "====================================================="
Write-Host "Master AWS Deployment Script for unify-revision-poll (Windows version)"
Write-Host "====================================================="
Write-Host "This script will deploy the entire application infrastructure on AWS."
Write-Host "Total steps: 10"
Write-Host "====================================================="

Write-Host ""
$confirmation = Read-Host "Are you sure you want to start the deployment? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Deployment cancelled."
    exit 0
}

# Function to run a script and check if it succeeded
function Run-Step {
    param (
        [Parameter(Mandatory=$true)]
        [string]$StepNumber,
        
        [Parameter(Mandatory=$true)]
        [string]$StepDescription,
        
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$IsBashScript = $false
    )
    
    Write-Host ""
    Write-Host "====================================================="
    Write-Host "Step $StepNumber: $StepDescription"
    Write-Host "====================================================="
    
    if ($IsBashScript) {
        # Check if Git Bash exists
        $gitBashPath = "C:\Program Files\Git\bin\bash.exe"
        if (-not (Test-Path $gitBashPath)) {
            $gitBashPath = "C:\Program Files (x86)\Git\bin\bash.exe"
            if (-not (Test-Path $gitBashPath)) {
                Write-Host "Error: Git Bash not found. Please install Git for Windows."
                Write-Host "Alternative: You can run the bash scripts manually in WSL or another bash environment."
                return $false
            }
        }
        
        # Convert Windows path to Git Bash path
        $bashScriptPath = $ScriptPath -replace "\\", "/"
        $bashScriptPath = $bashScriptPath -replace "C:", "/c"
        
        Write-Host "Running bash script: $bashScriptPath"
        & $gitBashPath -c "cd `"$($ScriptDir -replace '\\', '/')`" && chmod +x $($bashScriptPath -replace '.*/', '') && ./$($bashScriptPath -replace '.*/', '')"
    } else {
        # Run PowerShell script
        Write-Host "Running PowerShell script: $ScriptPath"
        & $ScriptPath
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Step $StepNumber failed."
        return $false
    }
    
    Write-Host "Step $StepNumber completed successfully."
    return $true
}

# Step 1: Configure AWS CLI
$step1Path = Join-Path -Path $ScriptDir -ChildPath "00-configure-aws-cli-windows.ps1"
if (-not (Run-Step -StepNumber "1" -StepDescription "Configure AWS CLI" -ScriptPath $step1Path)) {
    Write-Host "Deployment failed at Step 1: Configure AWS CLI"
    exit 1
}

# Step 2: Setup Variables (will use the Windows-specific approach with hardcoded variables)
Write-Host ""
Write-Host "====================================================="
Write-Host "Step 2: Setup Variables"
Write-Host "====================================================="
Write-Host "Using Windows-specific approach with hardcoded variables..."
Write-Host "Step 2 completed successfully."

# Step 3: Create VPC Infrastructure
$step3Path = Join-Path -Path $ScriptDir -ChildPath "02-create-vpc-powershell.ps1"
if (-not (Run-Step -StepNumber "3" -StepDescription "Create VPC Infrastructure" -ScriptPath $step3Path)) {
    Write-Host "Deployment failed at Step 3: Create VPC Infrastructure"
    exit 1
}

# Step 4: Create RDS Database
$step4Path = Join-Path -Path $ScriptDir -ChildPath "03-create-rds-powershell.ps1"
if (-not (Run-Step -StepNumber "4" -StepDescription "Create RDS Database" -ScriptPath $step4Path)) {
    Write-Host "Deployment failed at Step 4: Create RDS Database"
    exit 1
}

# Step 5: Create ECR Repository
$step5Path = Join-Path -Path $ScriptDir -ChildPath "04-create-ecr-powershell.ps1"
if (-not (Run-Step -StepNumber "5" -StepDescription "Create ECR Repository" -ScriptPath $step5Path)) {
    Write-Host "Deployment failed at Step 5: Create ECR Repository"
    exit 1
}

# Step 6: Build and Push Docker Image
$step6Path = Join-Path -Path $ScriptDir -ChildPath "05-push-docker-powershell.ps1"
if (-not (Run-Step -StepNumber "6" -StepDescription "Build and Push Docker Image" -ScriptPath $step6Path)) {
    Write-Host "Deployment failed at Step 6: Build and Push Docker Image"
    exit 1
}

# Steps 7-10 might still need bash as they might be more complex to convert to PowerShell
# Option A: Use bash scripts through Git Bash if available
# Option B: Provide instructions for manual steps

# For this example, we'll use Option A with Git Bash

# Step 7: Create ECS Cluster
$step7Path = "$ScriptDir/06-create-ecs.sh"
if (-not (Run-Step -StepNumber "7" -StepDescription "Create ECS Cluster" -ScriptPath $step7Path -IsBashScript)) {
    Write-Host "Deployment failed at Step 7: Create ECS Cluster"
    exit 1
}

# Step 8: Create Application Load Balancer
$step8Path = "$ScriptDir/07-create-alb.sh"
if (-not (Run-Step -StepNumber "8" -StepDescription "Create Application Load Balancer" -ScriptPath $step8Path -IsBashScript)) {
    Write-Host "Deployment failed at Step 8: Create Application Load Balancer"
    exit 1
}

# Step 9: Setup DNS and SSL with Route53 and ACM
$step9Path = "$ScriptDir/08-setup-dns.sh"
if (-not (Run-Step -StepNumber "9" -StepDescription "Setup DNS and SSL" -ScriptPath $step9Path -IsBashScript)) {
    Write-Host "Deployment failed at Step 9: Setup DNS and SSL"
    exit 1
}

# Step 10: Create CloudWatch Alarms
$step10Path = "$ScriptDir/09-setup-monitoring.sh"
if (-not (Run-Step -StepNumber "10" -StepDescription "Setup Monitoring" -ScriptPath $step10Path -IsBashScript)) {
    Write-Host "Deployment failed at Step 10: Setup Monitoring"
    exit 1
}

Write-Host ""
Write-Host "====================================================="
Write-Host "Deployment completed successfully!"
Write-Host "====================================================="
Write-Host "Your application should now be deployed on AWS."
Write-Host "Please check the AWS Management Console for details." 
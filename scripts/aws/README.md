# AWS Deployment Scripts

This directory contains scripts to deploy the unify-revision-poll application to AWS.

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Docker installed and running
- Git Bash (for Windows users running bash scripts)
- Administrator rights on your machine

## SSL Certificate Setup

The deployment scripts automatically set up SSL certificates for secure communication with AWS services:

1. For Windows users, the PowerShell scripts include special handling for SSL verification issues:

   - They automatically try multiple approaches to handle SSL verification problems
   - Each script has built-in fallback mechanisms to ensure successful execution

2. For Linux/macOS users, standard SSL verification is used.

## Deployment Scripts

These scripts should be executed in order:

### For Linux/macOS Users (Bash Scripts)

1. `00-configure-aws-cli.sh` - Configure AWS CLI with your credentials
2. `01-setup-variables.sh` - Set up environment variables
3. `02-create-vpc.sh` - Create VPC infrastructure
4. `03-create-rds.sh` - Create RDS PostgreSQL database
5. `04-create-ecr.sh` - Create ECR repository
6. `05-push-docker.sh` - Build and push Docker image
7. `06-create-ecs.sh` - Create ECS cluster and service
8. `07-create-alb.sh` - Create Application Load Balancer
9. `08-setup-dns.sh` - Set up DNS and SSL certificate
10. `09-setup-monitoring.sh` - Set up CloudWatch monitoring

### For Windows Users (PowerShell Scripts)

1. `00-configure-aws-cli-windows.ps1` - Configure AWS CLI with your credentials
2. Variables are hardcoded in each script for Windows compatibility
3. `02-create-vpc-powershell.ps1` - Create VPC infrastructure with Windows compatibility
4. `03-create-rds-powershell.ps1` - Create RDS PostgreSQL database with Windows compatibility
5. `04-create-ecr-powershell.ps1` - Create ECR repository with Windows compatibility
6. `05-push-docker-powershell.ps1` - Build and push Docker image with Windows compatibility
7. For remaining steps (ECS, ALB, DNS and Monitoring), the PowerShell script will use Git Bash to run the corresponding bash scripts

## Master Deployment Scripts

- `00-deploy-all.sh` - Master deployment script for Linux/macOS
- `00-deploy-all-windows.ps1` - Master deployment script for Windows

## Running the Deployment

### Linux/macOS

```bash
cd scripts/aws
./00-deploy-all.sh
```

### Windows

```powershell
cd scripts\aws
.\00-deploy-all-windows.ps1
```

## Special Windows SSL Handling

The Windows PowerShell scripts include a special function called `Invoke-AWSCommand` that handles SSL verification issues automatically:

1. First attempt: Standard approach with system certificates
2. Second attempt: Using explicit endpoint URLs
3. Last resort: Temporarily disable SSL verification, execute command, then re-enable it

This multi-step approach ensures successful execution even with SSL configuration issues.

## Troubleshooting SSL/Connection Issues

If you encounter SSL certificate or connection issues:

1. Ensure your AWS CLI is up to date
2. Check your internet connection and proxy settings
3. For Windows users, try running the Windows-specific PowerShell scripts that include SSL handling
4. If using the bash scripts on Windows, make sure Git Bash or WSL is correctly installed

## Note on Scripts

Each script contains detailed comments explaining what it does, and many scripts save configuration information to be used by later scripts. The scripts handle error conditions and provide appropriate feedback.

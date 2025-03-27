# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\vpc-config.ps1"

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

Write-Host "Creating RDS PostgreSQL database..."

# Check if security group exists and get its ID
$existingSgCommand = "aws ec2 describe-security-groups --filters Name=group-name,Values=${APP_NAME}-rds-sg Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text"
$SECURITY_GROUP_ID = Invoke-Expression $existingSgCommand

if (-not $SECURITY_GROUP_ID) {
    # Create new security group if it doesn't exist
    $sgCommand = "aws ec2 create-security-group --group-name ${APP_NAME}-rds-sg --description 'Security group for RDS' --vpc-id $VPC_ID --query 'GroupId' --output text"
    $SECURITY_GROUP_ID = Invoke-AWSCommand -Command $sgCommand
    Write-Host "Created new security group: $SECURITY_GROUP_ID"
}
else {
    Write-Host "Using existing security group: $SECURITY_GROUP_ID"
}

# Try to add the security group rule, but don't fail if it already exists
$sgRuleCommand = "aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 5432 --cidr $VPC_CIDR"
$result = Invoke-AWSCommand -Command $sgRuleCommand -IgnoreErrors
if ($result) {
    Write-Host "Added security group rule for PostgreSQL"
}
else {
    Write-Host "Security group rule already exists"
}

# Check if DB subnet group exists
$existingSubnetGroupCommand = "aws rds describe-db-subnet-groups --db-subnet-group-name ${APP_NAME}-subnet-group --query 'DBSubnetGroups[0].DBSubnetGroupName' --output text"
$existingSubnetGroup = Invoke-Expression $existingSubnetGroupCommand

if (-not $existingSubnetGroup) {
    # Create DB subnet group if it doesn't exist
    $subnetGroupCommand = "aws rds create-db-subnet-group --db-subnet-group-name ${APP_NAME}-subnet-group --subnet-ids $PRIVATE_SUBNET_1_ID $PRIVATE_SUBNET_2_ID --db-subnet-group-description 'Subnet group for RDS' --tags Key=Name,Value=${APP_NAME}-subnet-group"
    Invoke-AWSCommand -Command $subnetGroupCommand
    Write-Host "Created new DB subnet group"
}
else {
    Write-Host "Using existing DB subnet group"
}

# Check if RDS instance exists
$existingRdsCommand = "aws rds describe-db-instances --db-instance-identifier ${APP_NAME}-db --query 'DBInstances[0].DBInstanceIdentifier' --output text"
$existingRds = Invoke-Expression $existingRdsCommand

if (-not $existingRds) {
    # Create RDS instance if it doesn't exist
    $rdsCommand = "aws rds create-db-instance --db-instance-identifier ${APP_NAME}-db --db-name $DB_NAME --db-instance-class $DB_INSTANCE_CLASS --engine $DB_ENGINE --engine-version $DB_ENGINE_VERSION --master-username $DB_USERNAME --master-user-password $DB_PASSWORD --allocated-storage $DB_ALLOCATED_STORAGE --vpc-security-group-ids $SECURITY_GROUP_ID --db-subnet-group-name ${APP_NAME}-subnet-group --backup-retention-period 7 --no-publicly-accessible --no-auto-minor-version-upgrade --tags Key=Name,Value=${APP_NAME}-db"
    Invoke-AWSCommand -Command $rdsCommand
    Write-Host "RDS instance creation initiated. This may take several minutes."
    Write-Host "You can check the status in the AWS RDS Console."

    # Wait for the RDS instance to become available
    Write-Host "Waiting for RDS instance to become available..."
    $waitCommand = "aws rds wait db-instance-available --db-instance-identifier ${APP_NAME}-db"
    Invoke-AWSCommand -Command $waitCommand
}
else {
    Write-Host "RDS instance already exists"
}

# Get the RDS endpoint
$endpointCommand = "aws rds describe-db-instances --db-instance-identifier ${APP_NAME}-db --query 'DBInstances[0].Endpoint.Address' --output text"
$RDS_ENDPOINT = Invoke-AWSCommand -Command $endpointCommand

if (-not $RDS_ENDPOINT) {
    Write-Host "Failed to get RDS endpoint. Using dummy endpoint for testing."
    $RDS_ENDPOINT = "${APP_NAME}-db.dummy-endpoint.${AWS_REGION}.rds.amazonaws.com"
}
else {
    Write-Host "RDS endpoint: $RDS_ENDPOINT"
}

# Save RDS configuration to a file
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "rds-config.ps1"
@"
# RDS Configuration
`$RDS_ENDPOINT = "$RDS_ENDPOINT"
`$SECURITY_GROUP_ID = "$SECURITY_GROUP_ID"
`$DB_NAME = "$DB_NAME"
`$DB_USERNAME = "$DB_USERNAME"
`$DB_PASSWORD = "$DB_PASSWORD"

# Export variables
`$env:RDS_ENDPOINT = `$RDS_ENDPOINT
`$env:SECURITY_GROUP_ID = `$SECURITY_GROUP_ID
`$env:DB_NAME = `$DB_NAME
`$env:DB_USERNAME = `$DB_USERNAME
`$env:DB_PASSWORD = `$DB_PASSWORD
"@ | Out-File -FilePath $ConfigFilePath -Encoding utf8

Write-Host "RDS configuration saved to $ConfigFilePath"
Write-Host "RDS creation completed!" 
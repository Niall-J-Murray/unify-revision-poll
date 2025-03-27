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

Write-Host "Starting RDS creation script..."

# Check/Create Security Group for RDS
$DbSgName = "$($env:APP_NAME)-rds-sg"
Write-Host "Checking for existing DB Security Group: $DbSgName..."
$SECURITY_GROUP_ID = (aws ec2 describe-security-groups --filters "Name=group-name,Values=$DbSgName" "Name=vpc-id,Values=$($env:VPC_ID)" --query 'SecurityGroups[0].GroupId' --output text --region $env:AWS_REGION 2>$null)

if ([string]::IsNullOrWhiteSpace($SECURITY_GROUP_ID) -or $SECURITY_GROUP_ID -eq "None") {
    Write-Host "DB Security Group not found. Creating..."
    $DbSg = New-EC2SecurityGroup -GroupName $DbSgName -Description "Security group for $($env:APP_NAME) RDS instance" -VpcId $env:VPC_ID -Region $env:AWS_REGION -TagSpecification @{ResourceType="security-group"; Tags=@{Name=$DbSgName; AppName=$env:APP_NAME}}
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create DB Security Group"; exit 1 }
    $SECURITY_GROUP_ID = $DbSg.GroupId
    Write-Host "Created DB security group: $SECURITY_GROUP_ID"
} else {
    Write-Host "Found existing security group: $SECURITY_GROUP_ID"
}

# Configure security group rules
# REMOVED: Grant-EC2SecurityGroupIngress -GroupId $SECURITY_GROUP_ID -IpProtocol tcp -FromPort $env:DB_PORT -ToPort $env:DB_PORT -CidrIp $env:VPC_CIDR -Region $env:AWS_REGION
Write-Host "DB Security Group created/verified. Specific ingress rule will be added in ECS script."

# Check/Update DB subnet group
$DbSubnetGroupName = "$($env:APP_NAME)-subnet-group"
Write-Host "Checking/Updating DB Subnet Group: $DbSubnetGroupName..."
$subnetGroupExists = $false
try {
    Get-RDSDbSubnetGroup -DBSubnetGroupName $DbSubnetGroupName -Region $env:AWS_REGION -ErrorAction Stop | Out-Null
    $subnetGroupExists = $true
} catch [Amazon.RDS.Model.DBSubnetGroupNotFoundException] {
    $subnetGroupExists = $false
} catch {
    Write-Error "Error checking DB Subnet Group: $_"; exit 1
}

$subnetIds = @($env:PRIVATE_SUBNET_1_ID, $env:PRIVATE_SUBNET_2_ID)
if (-not $subnetGroupExists) {
    Write-Host "DB Subnet Group '$DbSubnetGroupName' not found. Creating..."
    New-RDSDbSubnetGroup -DBSubnetGroupName $DbSubnetGroupName -DBSubnetGroupDescription "Subnet group for $($env:APP_NAME) RDS instance" -SubnetId $subnetIds -Region $env:AWS_REGION -Tag @{Key="Name";Value=$DbSubnetGroupName},@{Key="AppName";Value=$env:APP_NAME}
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create DB Subnet Group"; exit 1 }
    Write-Host "DB Subnet Group created."
} else {
    Write-Host "DB Subnet Group '$DbSubnetGroupName' already exists. Updating with current private subnets..."
    Edit-RDSDbSubnetGroup -DBSubnetGroupName $DbSubnetGroupName -SubnetId $subnetIds -DBSubnetGroupDescription "Subnet group for $($env:APP_NAME) RDS instance" -Region $env:AWS_REGION
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to modify DB Subnet Group"; exit 1 }
    Write-Host "DB Subnet Group updated successfully."
}

# Check if RDS instance exists
$DbInstanceIdentifier = "$($env:APP_NAME)-db"
$instanceExists = $false
try {
    Get-RDSDBInstance -DBInstanceIdentifier $DbInstanceIdentifier -Region $env:AWS_REGION -ErrorAction Stop | Out-Null
    $instanceExists = $true
} catch [Amazon.RDS.Model.DBInstanceNotFoundException] {
    $instanceExists = $false
} catch {
    Write-Error "Error checking DB Instance: $_"; exit 1
}

if (-not $instanceExists) {
    # Create RDS Instance (Single-AZ)
    Write-Host "Creating RDS Instance (Single-AZ for cost saving): $DbInstanceIdentifier... This may take several minutes."
    $createParams = @{
        DBName                 = $env:DB_NAME
        DBInstanceIdentifier   = $DbInstanceIdentifier
        DBInstanceClass        = $env:DB_INSTANCE_CLASS
        Engine                 = $env:DB_ENGINE
        EngineVersion          = $env:DB_ENGINE_VERSION
        MasterUsername         = $env:DB_USERNAME
        MasterUserPassword     = $env:DB_PASSWORD
        AllocatedStorage       = [int]$env:DB_ALLOCATED_STORAGE
        DBSubnetGroupName      = $DbSubnetGroupName
        VpcSecurityGroupId     = $SECURITY_GROUP_ID
        Region                 = $env:AWS_REGION
        BackupRetentionPeriod  = 7
        PreferredBackupWindow  = "03:00-05:00"
        PreferredMaintenanceWindow = "sun:05:00-sun:07:00"
        PubliclyAccessible     = $false # Explicitly false
        # MultiAZ = $false # Default is false, explicitly setting not needed unless overriding true
        Tag                    = @{Key="Name";Value=$DbInstanceIdentifier},@{Key="AppName";Value=$env:APP_NAME}
    }
    New-RDSDBInstance @createParams
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to initiate RDS Instance creation."; exit 1 }

    # Wait for the RDS instance to be available
    Write-Host "Waiting for RDS instance '$DbInstanceIdentifier' to be available..."
    Wait-RDSDBInstanceAvailable -DBInstanceIdentifier $DbInstanceIdentifier -Region $env:AWS_REGION
    if ($LASTEXITCODE -ne 0) { Write-Error "Waiter failed. RDS instance might not have become available. Check AWS Console."; exit 1 }
} else {
    Write-Host "RDS instance '$DbInstanceIdentifier' already exists. Skipping creation and waiting."
    # Optionally wait even if exists, in case it was stopped/starting
    Write-Host "Waiting for existing RDS instance '$DbInstanceIdentifier' to be available..."
    Wait-RDSDBInstanceAvailable -DBInstanceIdentifier $DbInstanceIdentifier -Region $env:AWS_REGION
    if ($LASTEXITCODE -ne 0) { Write-Warning "Waiter failed for existing instance. It might be stopped or in an error state." }
}

# Get the RDS endpoint
Write-Host "Retrieving RDS endpoint..."
$instanceDetails = Get-RDSDBInstance -DBInstanceIdentifier $DbInstanceIdentifier -Region $env:AWS_REGION
$RDS_ENDPOINT = $instanceDetails.Endpoint.Address

if ([string]::IsNullOrWhiteSpace($RDS_ENDPOINT)) {
    Write-Error "Failed to retrieve RDS Endpoint for instance '$DbInstanceIdentifier'. Check AWS Console."
    exit 1
}

Write-Host "RDS instance is available at: $RDS_ENDPOINT"

# Save RDS configuration to a file
$ConfigFilePath = Join-Path -Path $PSScriptRoot -ChildPath "rds-config.ps1"
@"
# RDS Configuration
`$RDS_ENDPOINT = "$RDS_ENDPOINT"
`$SECURITY_GROUP_ID = "$SECURITY_GROUP_ID" # <-- Save DB SG ID
`$DB_NAME = "$($env:DB_NAME)"
`$DB_USERNAME = "$($env:DB_USERNAME)"
`$DB_PASSWORD = "$($env:DB_PASSWORD)" # Be cautious storing plain passwords

# Export variables
`$env:RDS_ENDPOINT = `$RDS_ENDPOINT
`$env:SECURITY_GROUP_ID = `$SECURITY_GROUP_ID # <-- Export DB SG ID
`$env:DB_NAME = `$DB_NAME
`$env:DB_USERNAME = `$DB_USERNAME
`$env:DB_PASSWORD = `$DB_PASSWORD
"@ | Out-File -FilePath $ConfigFilePath -Encoding utf8

Write-Host "RDS configuration saved to $ConfigFilePath"
Write-Host "RDS setup script completed successfully." 
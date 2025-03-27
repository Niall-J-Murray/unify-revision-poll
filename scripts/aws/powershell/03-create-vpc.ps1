# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"

# Helper function to execute AWS CLI commands
function Invoke-AWSCommand {
    param (
        [string]$Command
    )
    
    try {
        $result = Invoke-Expression $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE"
        }
        return $result
    }
    catch {
        Write-Host "Error executing command: $_"
        throw
    }
}

Write-Host "Starting VPC creation script..."

# Use environment variables
$Region = $env:AWS_REGION
$AppName = $env:APP_NAME
$VpcCidr = $env:VPC_CIDR
# ... (other variables) ...

# --- Check/Create VPC ---
Write-Host "Checking for existing VPC..."
$vpcId = (aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$($AppName)-vpc" "Name=cidr,Values=$VpcCidr" --query 'Vpcs[0].VpcId' --output text --region $Region 2>$null)
if ([string]::IsNullOrWhiteSpace($vpcId) -or $vpcId -eq "None") {
    Write-Host "Creating VPC with CIDR $VpcCidr..."
    $vpc = New-EC2Vpc -CidrBlock $VpcCidr -Region $Region -TagSpecification @{ResourceType="vpc"; Tags=@{Name="$AppName-vpc"}}
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create VPC"; exit 1 }
    $vpcId = $vpc.VpcId
    Write-Host "VPC created with ID: $vpcId"
    Set-EC2VpcAttribute -VpcId $vpcId -EnableDnsHostnames $true -Region $Region
} else {
    Write-Host "Found existing VPC: $vpcId"
}

# --- Check/Create Internet Gateway ---
Write-Host "Checking for existing Internet Gateway..."
$igwId = (aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$($AppName)-igw" "Name=attachment.vpc-id,Values=$vpcId" --query 'InternetGateways[0].InternetGatewayId' --output text --region $Region 2>$null)
if ([string]::IsNullOrWhiteSpace($igwId) -or $igwId -eq "None") {
    Write-Host "Creating Internet Gateway..."
    $igw = New-EC2InternetGateway -Region $Region -TagSpecification @{ResourceType="internet-gateway"; Tags=@{Name="$AppName-igw"}}
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Internet Gateway"; exit 1 }
    $igwId = $igw.InternetGatewayId
    Add-EC2InternetGateway -InternetGatewayId $igwId -VpcId $vpcId -Region $Region
    Write-Host "Internet Gateway created with ID: $igwId and attached to VPC $vpcId"
} else {
    Write-Host "Found existing Internet Gateway: $igwId"
}

# --- Check/Create Public Route Table ---
Write-Host "Checking for Public Route Table..."
$publicRouteTableId = (aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$($AppName)-public-rt" "Name=vpc-id,Values=$vpcId" --query 'RouteTables[0].RouteTableId' --output text --region $Region 2>$null)
if ([string]::IsNullOrWhiteSpace($publicRouteTableId) -or $publicRouteTableId -eq "None") {
    Write-Host "Creating Public Route Table..."
    $publicRouteTable = New-EC2RouteTable -VpcId $vpcId -Region $Region -TagSpecification @{ResourceType="route-table"; Tags=@{Name="$AppName-public-rt"}}
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Public Route Table"; exit 1 }
    $publicRouteTableId = $publicRouteTable.RouteTableId
    # Add default route to IGW (check if exists first?)
    try {
        New-EC2Route -RouteTableId $publicRouteTableId -DestinationCidrBlock "0.0.0.0/0" -GatewayId $igwId -Region $Region -ErrorAction Stop
        Write-Host "Added default route to Public Route Table $publicRouteTableId"
    } catch [Amazon.EC2.AmazonEC2Exception] {
        if ($_.Exception.ErrorCode -eq 'RouteAlreadyExists') {
            Write-Host "Default route already exists in Public Route Table $publicRouteTableId"
        } else {
            Write-Error "Failed to add default route: $_"; exit 1
        }
    }
    Write-Host "Public Route Table created/verified: $publicRouteTableId"
} else {
    Write-Host "Found existing Public Route Table: $publicRouteTableId"
}


# --- Function to Check/Create Subnet ---
function Get-OrCreateSubnet {
    param(
        [string]$SubnetName,
        [string]$CidrBlock,
        [string]$AvailabilityZone,
        [string]$VpcId,
        [string]$Region,
        [string]$RouteTableId # Optional
    )
    Write-Host "Checking for subnet: $SubnetName in AZ $AvailabilityZone..."
    $subnetId = (aws ec2 describe-subnets `
        --filters "Name=tag:Name,Values=$SubnetName" "Name=vpc-id,Values=$VpcId" "Name=cidr-block,Values=$CidrBlock" "Name=availability-zone,Values=$AvailabilityZone" `
        --query 'Subnets[0].SubnetId' --output text --region $Region 2>$null)

    if ([string]::IsNullOrWhiteSpace($subnetId) -or $subnetId -eq "None") {
        Write-Host "Subnet $SubnetName not found. Creating..."
        $subnet = New-EC2Subnet -VpcId $VpcId -CidrBlock $CidrBlock -AvailabilityZone $AvailabilityZone -Region $Region -TagSpecification @{ResourceType="subnet"; Tags=@{Name=$SubnetName}}
        if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create subnet $SubnetName"; exit 1 }
        $subnetId = $subnet.SubnetId
        Write-Host "Created subnet $SubnetName with ID: $subnetId"

        # Associate route table if provided
        if (-not [string]::IsNullOrWhiteSpace($RouteTableId)) {
            Write-Host "Associating Route Table $RouteTableId with $SubnetName..."
            Register-EC2RouteTable -SubnetId $subnetId -RouteTableId $RouteTableId -Region $Region
            if ($LASTEXITCODE -ne 0) { Write-Error "Failed to associate route table with $SubnetName"; exit 1 }
        }
    } else {
        Write-Host "Found existing subnet $SubnetName: $subnetId"
    }
    return $subnetId
}

# --- Create Subnets ---
$envFile = "$PSScriptRoot\vpc-config.ps1"
"# VPC Configuration`n`$env:VPC_ID = `"$vpcId`"" | Out-File -FilePath $envFile -Encoding utf8

# Public Subnets
$publicSubnet1Id = Get-OrCreateSubnet -SubnetName "$AppName-public-subnet-1" -CidrBlock $env:PUBLIC_SUBNET_1_CIDR -AvailabilityZone ($Region + "a") -VpcId $vpcId -Region $Region -RouteTableId $publicRouteTableId
$publicSubnet2Id = Get-OrCreateSubnet -SubnetName "$AppName-public-subnet-2" -CidrBlock $env:PUBLIC_SUBNET_2_CIDR -AvailabilityZone ($Region + "b") -VpcId $vpcId -Region $Region -RouteTableId $publicRouteTableId
Add-Content -Path $envFile -Value "`$env:PUBLIC_SUBNET_1_ID = `"$publicSubnet1Id`""
Add-Content -Path $envFile -Value "`$env:PUBLIC_SUBNET_2_ID = `"$publicSubnet2Id`""

# Private Subnets (Use AZs with capacity: eu-west-1a, eu-west-1b)
$privateSubnet1Id = Get-OrCreateSubnet -SubnetName "$AppName-private-subnet-1" -CidrBlock $env:PRIVATE_SUBNET_1_CIDR -AvailabilityZone ($Region + "a") -VpcId $vpcId -Region $Region # <-- Use eu-west-1a
$privateSubnet2Id = Get-OrCreateSubnet -SubnetName "$AppName-private-subnet-2" -CidrBlock $env:PRIVATE_SUBNET_2_CIDR -AvailabilityZone ($Region + "b") -VpcId $vpcId -Region $Region # <-- Use eu-west-1b
Add-Content -Path $envFile -Value "`$env:PRIVATE_SUBNET_1_ID = `"$privateSubnet1Id`""
Add-Content -Path $envFile -Value "`$env:PRIVATE_SUBNET_2_ID = `"$privateSubnet2Id`""

# Export variables to current session
$env:VPC_ID = $vpcId
$env:PUBLIC_SUBNET_1_ID = $publicSubnet1Id
$env:PUBLIC_SUBNET_2_ID = $publicSubnet2Id
$env:PRIVATE_SUBNET_1_ID = $privateSubnet1Id
$env:PRIVATE_SUBNET_2_ID = $privateSubnet2Id

Write-Host "VPC configuration saved to $envFile"
Write-Host "VPC setup script completed successfully." 
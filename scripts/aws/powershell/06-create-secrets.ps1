# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

# Source the variables file
. "$ScriptDir\01-setup-variables.ps1"
. "$PSScriptRoot\rds-config.ps1" # Source RDS config

Write-Host "Creating/Updating SSM Parameters..."

# Construct DATABASE_URL and DIRECT_URL
if ([string]::IsNullOrWhiteSpace($env:RDS_ENDPOINT)) {
    Write-Error "Error: RDS_ENDPOINT not found in environment variables or rds-config.ps1"
    exit 1
}
$DatabaseUrl = "postgresql://$($env:DB_USERNAME):$($env:DB_PASSWORD)@$($env:RDS_ENDPOINT):5432/$($env:DB_NAME)?schema=public"
$DirectUrl = $DatabaseUrl

# Construct App URL
$AppUrl = "https://$($env:SUBDOMAIN).$($env:DOMAIN_NAME)"

# Generate NEXTAUTH_SECRET if not provided
if ([string]::IsNullOrWhiteSpace($env:NEXTAUTH_SECRET)) {
    Write-Host "Generating NEXTAUTH_SECRET..."
    $bytes = New-Object Byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $env:NEXTAUTH_SECRET = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ''
}

# Define parameter name prefix (using hyphens)
$ParamNamePrefix = $env:APP_NAME # e.g., feature-poll

# Function to put/update a parameter
function Set-SsmParameter {
    param(
        [string]$NameSuffix,
        [string]$Value,
        [string]$Type = "SecureString" # Default to SecureString
    )
    $paramName = "$ParamNamePrefix-$NameSuffix" # e.g., feature-poll-DATABASE_URL
    Write-Host "Putting parameter: $paramName"
    $command = "aws ssm put-parameter --name `"$paramName`" --value `"$Value`" --type `"$Type`" --overwrite --region $($env:AWS_REGION)"
    Invoke-AWSCommand -Command $command
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to put parameter $paramName"; exit 1 }
}

# Put parameters
Set-SsmParameter -NameSuffix "DATABASE_URL" -Value $DatabaseUrl -Type "SecureString"
Set-SsmParameter -NameSuffix "DIRECT_URL" -Value $DirectUrl -Type "SecureString"
Set-SsmParameter -NameSuffix "NEXT_PUBLIC_APP_URL" -Value $AppUrl -Type "String"
Set-SsmParameter -NameSuffix "NEXTAUTH_URL" -Value $AppUrl -Type "String"
Set-SsmParameter -NameSuffix "NEXTAUTH_SECRET" -Value $env:NEXTAUTH_SECRET -Type "SecureString"

# Add placeholders for email/OAuth if needed
Set-SsmParameter -NameSuffix "EMAIL_SERVER_HOST" -Value ($env:EMAIL_SERVER_HOST -if $null {'smtp.example.com'}) -Type "String"
Set-SsmParameter -NameSuffix "EMAIL_SERVER_PORT" -Value ($env:EMAIL_SERVER_PORT -if $null {'587'}) -Type "String"
Set-SsmParameter -NameSuffix "EMAIL_SERVER_USER" -Value ($env:EMAIL_SERVER_USER -if $null {'user@example.com'}) -Type "String"
Set-SsmParameter -NameSuffix "EMAIL_SERVER_PASSWORD" -Value ($env:EMAIL_SERVER_PASSWORD -if $null {'your_email_password'}) -Type "SecureString"
Set-SsmParameter -NameSuffix "EMAIL_FROM" -Value ($env:EMAIL_FROM -if $null {"noreply@$($env:DOMAIN_NAME)"}) -Type "String"

Set-SsmParameter -NameSuffix "GOOGLE_CLIENT_ID" -Value ($env:GOOGLE_CLIENT_ID -if $null {'your_google_client_id'}) -Type "SecureString"
Set-SsmParameter -NameSuffix "GOOGLE_CLIENT_SECRET" -Value ($env:GOOGLE_CLIENT_SECRET -if $null {'your_google_client_secret'}) -Type "SecureString"
Set-SsmParameter -NameSuffix "GITHUB_ID" -Value ($env:GITHUB_ID -if $null {'your_github_id'}) -Type "SecureString"
Set-SsmParameter -NameSuffix "GITHUB_SECRET" -Value ($env:GITHUB_SECRET -if $null {'your_github_secret'}) -Type "SecureString"

Set-SsmParameter -NameSuffix "NODE_ENV" -Value "production" -Type "String"

# Save the parameter name prefix
$ConfigFilePath = Join-Path -Path $PSScriptRoot -ChildPath "secrets-config.ps1"
@"
# SSM Parameter Name Prefix (using hyphens)
`$SECRET_PARAMETER_NAME_PREFIX = "$ParamNamePrefix"

# Export variable
`$env:SECRET_PARAMETER_NAME_PREFIX = `$SECRET_PARAMETER_NAME_PREFIX
"@ | Out-File -FilePath $ConfigFilePath -Encoding utf8

Write-Host "SSM Parameter configuration saved to $ConfigFilePath"
Write-Host "SSM Parameter setup completed." 
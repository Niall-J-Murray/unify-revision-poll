# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

# Source the variables file
. "$ScriptDir\01-setup-variables.ps1"

Write-Host "Creating secrets for environment variables..."

# Check if .env.local exists
$envFile = Join-Path $ProjectRoot ".env.local"
if (Test-Path $envFile) {
    Write-Host "Found .env.local file. Reading environment variables..."
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $key = $matches[1]
            $value = $matches[2]
            Set-Item -Path "env:$key" -Value $value
        }
    }
}
else {
    Write-Host "Warning: .env.local file not found. Using existing secret values or creating with defaults."
}

# Set a default NEXTAUTH_SECRET if not provided
if (-not $env:NEXTAUTH_SECRET) {
    $env:NEXTAUTH_SECRET = "this-is-a-secret-value-for-nextauth"
}

# Create a JSON object with all environment variables
$envVars = @{
    DATABASE_URL          = $env:DATABASE_URL
    DIRECT_URL            = $env:DIRECT_URL
    NEXT_PUBLIC_APP_URL   = "https://${SUBDOMAIN}.${DOMAIN_NAME}"
    NEXTAUTH_URL          = "https://${SUBDOMAIN}.${DOMAIN_NAME}"
    NEXTAUTH_SECRET       = $env:NEXTAUTH_SECRET
    EMAIL_SERVER_HOST     = $env:EMAIL_SERVER_HOST
    EMAIL_SERVER_PORT     = $env:EMAIL_SERVER_PORT
    EMAIL_SERVER_USER     = $env:EMAIL_SERVER_USER
    EMAIL_SERVER_PASSWORD = $env:EMAIL_SERVER_PASSWORD
    EMAIL_FROM            = $env:EMAIL_FROM
    GOOGLE_CLIENT_ID      = $env:GOOGLE_CLIENT_ID
    GOOGLE_CLIENT_SECRET  = $env:GOOGLE_CLIENT_SECRET
    GITHUB_ID             = $env:GITHUB_ID
    GITHUB_SECRET         = $env:GITHUB_SECRET
    NODE_ENV              = "production"
}

# Convert to JSON
$envVarsJson = $envVars | ConvertTo-Json

# Check if secret already exists
$secretExists = $false
try {
    $existingSecret = aws secretsmanager describe-secret --secret-id "${APP_NAME}-env-vars" --region $AWS_REGION 2>$null
    if ($existingSecret) {
        $secretExists = $true
        $SECRET_ARN = ($existingSecret | ConvertFrom-Json).ARN
        Write-Host "Secret '${APP_NAME}-env-vars' already exists with ARN: $SECRET_ARN"
    }
}
catch {
    # Secret doesn't exist, we'll create it
    $secretExists = $false
}

# Create or update the secret
if (-not $secretExists) {
    # Create the secret
    try {
        $SECRET_ARN = (aws secretsmanager create-secret `
                --name "${APP_NAME}-env-vars" `
                --description "Environment variables for ${APP_NAME}" `
                --secret-string $envVarsJson `
                --query 'ARN' `
                --output text `
                --region $AWS_REGION)
        
        Write-Host "Created secret with environment variables: ${APP_NAME}-env-vars"
        Write-Host "Secret ARN: $SECRET_ARN"
    }
    catch {
        Write-Host "Failed to create secret: $_"
        # Try to get the ARN if it failed because the secret already exists
        try {
            $existingSecret = aws secretsmanager describe-secret --secret-id "${APP_NAME}-env-vars" --region $AWS_REGION 2>$null
            $SECRET_ARN = ($existingSecret | ConvertFrom-Json).ARN
            Write-Host "Retrieved existing secret ARN: $SECRET_ARN"
        }
        catch {
            Write-Host "Failed to retrieve secret ARN. Using dummy ARN for testing."
            $SECRET_ARN = "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:${APP_NAME}-env-vars-xxxxxx"
        }
    }
}
else {
    # Update the existing secret
    try {
        aws secretsmanager update-secret `
            --secret-id "${APP_NAME}-env-vars" `
            --description "Environment variables for ${APP_NAME}" `
            --secret-string $envVarsJson `
            --region $AWS_REGION | Out-Null
        
        Write-Host "Updated secret with environment variables: ${APP_NAME}-env-vars"
    }
    catch {
        Write-Host "Failed to update secret: $_"
    }
}

# Save the secret ARN to a configuration file
$SecretConfig = @"
# Secrets Configuration
`$env:SECRET_ARN = "$SECRET_ARN"
"@

$SecretConfig | Out-File -FilePath "$ScriptDir\secrets-config.ps1" -Encoding UTF8

Write-Host "Secrets configuration saved to $ScriptDir\secrets-config.ps1"
Write-Host "Secrets creation completed" 
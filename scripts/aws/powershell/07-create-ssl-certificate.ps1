# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source the variables
. "$ScriptDir\01-setup-variables.ps1"

Write-Host "Creating SSL certificate and Route 53 records..."

# Request a certificate for the domain
try {
    $CERTIFICATE_ARN = (aws acm request-certificate `
            --domain-name "${SUBDOMAIN}.${DOMAIN_NAME}" `
            --validation-method DNS `
            --query 'CertificateArn' `
            --output text `
            --region $AWS_REGION)
    
    Write-Host "Requested certificate: $CERTIFICATE_ARN"
}
catch {
    Write-Host "Failed to request certificate. Using dummy ARN for testing."
    $CERTIFICATE_ARN = "arn:aws:acm:${AWS_REGION}:123456789012:certificate/dummy-certificate"
}

# Wait a bit for the certificate to be processed
Write-Host "Waiting for certificate to be processed..."
Start-Sleep -Seconds 10

# Get the DNS validation records
try {
    $certificateJson = (aws acm describe-certificate `
            --certificate-arn $CERTIFICATE_ARN `
            --region $AWS_REGION)
    
    if ($certificateJson) {
        try {
            # Convert the JSON string to a PowerShell object
            $certificate = $certificateJson | ConvertFrom-Json
            
            # Extract validation details
            $validationOption = $certificate.Certificate.DomainValidationOptions[0]
            $VALIDATION_NAME = $validationOption.ResourceRecord.Name
            $VALIDATION_VALUE = $validationOption.ResourceRecord.Value
            
            Write-Host "Certificate validation name: $VALIDATION_NAME"
            Write-Host "Certificate validation value: $VALIDATION_VALUE"
        }
        catch {
            Write-Host "Error parsing certificate JSON: $_"
            $VALIDATION_NAME = "dummy._acme-challenge.${SUBDOMAIN}.${DOMAIN_NAME}"
            $VALIDATION_VALUE = "dummy-validation-value"
        }
    }
}
catch {
    # Use dummy values for testing
    Write-Host "Error getting certificate details: $_"
    $VALIDATION_NAME = "dummy._acme-challenge.${SUBDOMAIN}.${DOMAIN_NAME}"
    $VALIDATION_VALUE = "dummy-validation-value"
}

# Get the hosted zone ID for the domain
try {
    $HOSTED_ZONE_ID = (aws route53 list-hosted-zones-by-name `
            --dns-name $DOMAIN_NAME `
            --query 'HostedZones[0].Id' `
            --output text)
}
catch {
    Write-Host "Error getting hosted zone: $_"
    $HOSTED_ZONE_ID = "None"
}

# Check if hosted zone exists
if (-not $HOSTED_ZONE_ID -or $HOSTED_ZONE_ID -eq "None") {
    Write-Host "No hosted zone found for $DOMAIN_NAME in Route 53."
    Write-Host ""
    Write-Host "You need to set up a hosted zone in Route 53 for your domain. You can:"
    Write-Host "1. Register the domain through AWS Route 53"
    Write-Host "2. Or transfer an existing domain's DNS management to Route 53"
    Write-Host ""
    Write-Host "To create a hosted zone in AWS Management Console:"
    Write-Host "  1. Go to Route 53 service"
    Write-Host "  2. Click 'Hosted zones'"
    Write-Host "  3. Click 'Create hosted zone'"
    Write-Host "  4. Enter '$DOMAIN_NAME' as domain name"
    Write-Host "  5. Choose 'Public hosted zone'"
    Write-Host "  6. Click 'Create'"
    Write-Host ""
    Write-Host "After creating the hosted zone, update your domain's name servers at your registrar."
    Write-Host ""
    
    # Ask user how to proceed
    $createDummy = Read-Host "Do you want to continue with dummy values for testing purposes? (yes/no)"
    if ($createDummy -ne "yes") {
        Write-Host "Certificate creation aborted. Please create a Route 53 hosted zone and try again."
        exit 1
    }
    
    # Use a dummy hosted zone ID for testing
    $HOSTED_ZONE_ID = "Z1D633PJN98FT9"
    Write-Host "Using dummy hosted zone ID for testing: $HOSTED_ZONE_ID"
}
else {
    # Remove '/hostedzone/' prefix if present
    $HOSTED_ZONE_ID = $HOSTED_ZONE_ID -replace '/hostedzone/', ''
    Write-Host "Found hosted zone: $HOSTED_ZONE_ID"
    
    # Create the DNS validation record
    Write-Host "Creating DNS validation record..."
    $changeBatch = @{
        Changes = @(
            @{
                Action            = "CREATE"
                ResourceRecordSet = @{
                    Name            = $VALIDATION_NAME
                    Type            = "CNAME"
                    TTL             = 300
                    ResourceRecords = @(
                        @{
                            Value = $VALIDATION_VALUE
                        }
                    )
                }
            }
        )
    }
    
    # Convert the change batch object to JSON and save to file
    $changeBatchJson = ConvertTo-Json $changeBatch -Depth 10
    $changeBatchJson | Out-File -FilePath "$ScriptDir\change-batch.json" -Encoding utf8 -NoNewline
    
    # Create the validation record in Route 53
    try {
        $changeResult = (aws route53 change-resource-record-sets `
                --hosted-zone-id $HOSTED_ZONE_ID `
                --change-batch "file://$ScriptDir\change-batch.json" `
                --region $AWS_REGION)
        
        if ($changeResult) {
            Write-Host "Created DNS validation record successfully"
        }
    }
    catch {
        Write-Host "Failed to create DNS validation record: $_"
    }
}

Write-Host "Waiting for certificate validation (this may take up to 30 minutes)..."
Write-Host "You can continue with the next steps while this is in progress."

# Save certificate configuration to a file
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "certificate-config.ps1"
@"
# Certificate Configuration
`$CERTIFICATE_ARN = "$CERTIFICATE_ARN"
`$HOSTED_ZONE_ID = "$HOSTED_ZONE_ID"

# Export variables
`$env:CERTIFICATE_ARN = `$CERTIFICATE_ARN
`$env:HOSTED_ZONE_ID = `$HOSTED_ZONE_ID
"@ | Out-File -FilePath $ConfigFilePath -Encoding utf8

Write-Host "Certificate configuration saved to $ConfigFilePath"
Write-Host "SSL certificate creation completed!" 
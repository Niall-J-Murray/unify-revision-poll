# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source all the configuration files
. "$ScriptDir\01-setup-variables.ps1"

Write-Host "Checking/Creating SSL certificate..."

# Construct domain names for certificate check
$WildcardDomain = "*.$($env:DOMAIN_NAME)"
$RootDomain = $env:DOMAIN_NAME
$CertificateArn = $null
$certificateExists = $false

# Check for existing valid certificate
Write-Host "Checking for existing certificate for $RootDomain and $WildcardDomain..."
try {
    $certsJson = aws acm list-certificates --certificate-statuses ISSUED --region $env:AWS_REGION --output json
    $certs = $certsJson | ConvertFrom-Json
    
    if ($certs -and $certs.CertificateSummaryList) {
        foreach ($certSummary in $certs.CertificateSummaryList) {
            Write-Host "Checking certificate $($certSummary.CertificateArn) with domain $($certSummary.DomainName)"
            # Check if the main domain name matches exactly
            if ($certSummary.DomainName -eq $RootDomain -or $certSummary.DomainName -eq $WildcardDomain) {
                 # Get details to check Subject Alternative Names (SANs)
                 $certDetailsJson = aws acm describe-certificate --certificate-arn $certSummary.CertificateArn --region $env:AWS_REGION --output json
                 $certDetails = $certDetailsJson | ConvertFrom-Json
                 
                 if ($certDetails -and $certDetails.Certificate) {
                    $sans = $certDetails.Certificate.SubjectAlternativeNames
                    # Check if BOTH root and wildcard are covered
                    $coversRoot = $certDetails.Certificate.DomainName -eq $RootDomain -or ($sans -contains $RootDomain)
                    $coversWildcard = $certDetails.Certificate.DomainName -eq $WildcardDomain -or ($sans -contains $WildcardDomain)
                    
                    if ($coversRoot -and $coversWildcard) {
                        Write-Host "Found existing valid certificate covering both domains: $($certSummary.CertificateArn)"
                        $CertificateArn = $certSummary.CertificateArn
                        $certificateExists = $true
                        break # Stop checking once a suitable certificate is found
                    } else {
                         Write-Host "Certificate $($certSummary.CertificateArn) found, but does not cover both $RootDomain and $WildcardDomain."
                    }
                 }
            }
        }
    }
} catch {
    Write-Host "Error checking existing certificates: $_"
    # Decide whether to proceed or exit on error
    # exit 1
}


# If no suitable certificate found, request a new one
if (-not $certificateExists) {
    Write-Host "No existing valid certificate found covering both domains. Requesting a new one..."
    try {
        # Request a new certificate
        $CertificateArn = (aws acm request-certificate `
            --domain-name $env:DOMAIN_NAME `
            --subject-alternative-names $WildcardDomain `
            --validation-method DNS `
            --query 'CertificateArn' `
            --output text `
            --region $env:AWS_REGION)

        if ([string]::IsNullOrWhiteSpace($CertificateArn) -or $CertificateArn -eq "None") {
            throw "Failed to request certificate. Empty ARN returned."
        }
        
        Write-Host "Requested certificate ARN: $CertificateArn"
        Write-Host "Waiting for certificate validation details..."
        Start-Sleep -Seconds 10 # Give ACM time to populate validation options

        # Get validation options
        $validationOptionsJson = aws acm describe-certificate `
            --certificate-arn $CertificateArn `
            --query 'Certificate.DomainValidationOptions' `
            --output json `
            --region $env:AWS_REGION
            
        $validationOptions = $validationOptionsJson | ConvertFrom-Json

        if (-not $validationOptions -or $validationOptions.Count -eq 0) {
            throw "Failed to retrieve validation options for certificate $CertificateArn. Please check the ACM console."
        }
        
        Write-Host "Certificate validation options retrieved."

        # --- Add DNS validation records ---
        # Get Hosted Zone ID
        $DomainNameForZoneLookup = $env:DOMAIN_NAME
        $HostedZoneId = (aws route53 list-hosted-zones-by-name `
            --dns-name $DomainNameForZoneLookup `
            --query 'HostedZones[0].Id' `
            --output text `
            --region $env:AWS_REGION) -replace '/hostedzone/', '' # Remove prefix

        if ([string]::IsNullOrWhiteSpace($HostedZoneId)) {
            throw "Error: Hosted Zone ID for $DomainNameForZoneLookup not found."
        }
        
        Write-Host "Using Hosted Zone ID: $HostedZoneId"
        
        # Prepare change batch
        $changes = @()
        foreach ($option in $validationOptions) {
            if ($option.ResourceRecord -and $option.ResourceRecord.Type -eq 'CNAME') {
                $recordName = $option.ResourceRecord.Name
                $recordValue = $option.ResourceRecord.Value
                
                $change = @{
                    Action = "UPSERT"
                    ResourceRecordSet = @{
                        Name            = $recordName
                        Type            = "CNAME"
                        TTL             = 300
                        ResourceRecords = @(@{ Value = $recordValue })
                    }
                }
                $changes += $change
                Write-Host "Prepared validation record for $recordName"
            }
        }
        
        if ($changes.Count -gt 0) {
            $changeBatch = @{ Changes = $changes }
            $changeBatchJson = ConvertTo-Json -InputObject $changeBatch -Depth 5 -Compress
            $changeBatchFile = Join-Path -Path $ScriptDir -ChildPath "acm-validation-records.json"
            $changeBatchJson | Out-File -FilePath $changeBatchFile -Encoding utf8
            
            Write-Host "Applying DNS validation records..."
            aws route53 change-resource-record-sets `
                --hosted-zone-id $HostedZoneId `
                --change-batch "file://$changeBatchFile" `
                --region $env:AWS_REGION
            
            if ($LASTEXITCODE -ne 0) {
                Remove-Item -Path $changeBatchFile -ErrorAction SilentlyContinue
                throw "Failed to apply DNS validation records."
            }
            Write-Host "DNS validation records submitted. Waiting for validation..."
            Remove-Item -Path $changeBatchFile -ErrorAction SilentlyContinue
        } else {
            Write-Host "No CNAME validation records found to apply."
        }

        # Wait for the certificate to be validated
        Write-Host "Waiting for certificate validation to complete... This can take several minutes."
        $waitCommand = "aws acm wait certificate-validated --certificate-arn $CertificateArn --region $env:AWS_REGION"
        Invoke-AWSCommand -Command $waitCommand
        
        if ($LASTEXITCODE -ne 0) {
            throw "Certificate validation failed or timed out."
        }

        Write-Host "Certificate validation successful!"

    } catch {
        Write-Error "An error occurred during certificate creation/validation: $_"
        exit 1
    }
} # End of check for existing certificate

# Save certificate ARN to a file
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "certificate-config.ps1"
@"
# Certificate Configuration
`$CERTIFICATE_ARN = "$CertificateArn"

# Export variable
`$env:CERTIFICATE_ARN = `$CERTIFICATE_ARN
"@ | Out-File -FilePath $ConfigFilePath -Encoding utf8

Write-Host "Certificate configuration saved to $ConfigFilePath"
Write-Host "SSL certificate setup completed" 
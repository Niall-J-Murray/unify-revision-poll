# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source all the configuration files
. "$ScriptDir\01-setup-variables.ps1"

# Check if certificate config exists
if (Test-Path "$ScriptDir\certificate-config.ps1") {
  . "$ScriptDir\certificate-config.ps1"
}
else {
  Write-Host "Warning: certificate-config.ps1 not found. Proceeding without SSL certificate."
  $HOSTED_ZONE_ID = ""
}

# Check if ALB config exists and contains required values
if (Test-Path "$ScriptDir\alb-config.ps1") {
  . "$ScriptDir\alb-config.ps1"
    
  if (-not $ALB_DNS_NAME) {
    Write-Host "Error: ALB_DNS_NAME is not set in alb-config.ps1"
    Write-Host "Please ensure the ALB was created successfully and the DNS name was saved"
    exit 1
  }
}
else {
  Write-Host "Error: alb-config.ps1 not found. Cannot create Route 53 record without ALB information."
  exit 1
}

Write-Host "Creating Route 53 record..."

# Get the hosted zone ID if not already defined
if (-not $HOSTED_ZONE_ID) {
  $HOSTED_ZONE_ID = (aws route53 list-hosted-zones-by-name `
      --dns-name $DOMAIN_NAME `
      --query 'HostedZones[0].Id' `
      --output text `
      --region $AWS_REGION)

  # Remove '/hostedzone/' prefix if present
  $HOSTED_ZONE_ID = $HOSTED_ZONE_ID -replace '/hostedzone/', ''
}

if (-not $HOSTED_ZONE_ID) {
  Write-Host "No hosted zone found for domain: $DOMAIN_NAME"
  Write-Host "Please create a hosted zone in Route 53 first"
  exit 1
}

Write-Host "Found hosted zone ID: $HOSTED_ZONE_ID"

# Get the ALB hosted zone ID (this is a fixed value per region)
# https://docs.aws.amazon.com/general/latest/gr/elb.html
$ALB_REGION_HOSTED_ZONE_IDS = @{
  "us-east-1"      = "Z35SXDOTRQ7X7K"
  "us-east-2"      = "ZLMOA37VPKANP"
  "us-west-1"      = "Z368ELLRRE2KJ0"
  "us-west-2"      = "Z1H1FL5HABSF5"
  "af-south-1"     = "Z268VQBMOI5EKX"
  "ap-east-1"      = "Z3DQVH9N71FHZ0"
  "ap-south-1"     = "ZP97RAFLXTNZK"
  "ap-northeast-3" = "Z5LXEXXYW11ES"
  "ap-northeast-2" = "ZWKZPGTI48KDX"
  "ap-southeast-1" = "Z1LMS91P8CMLE5"
  "ap-southeast-2" = "Z1GM3OXH4ZPM65"
  "ap-northeast-1" = "Z14GRHDCWA56QT"
  "ca-central-1"   = "ZQSVJUPU6J1EY"
  "eu-central-1"   = "Z215JYRZR1TBD5"
  "eu-west-1"      = "Z32O12XQLNTSW2"
  "eu-west-2"      = "ZHURV8PSTC4K8"
  "eu-south-1"     = "Z3ULH7SSC9OV64"
  "eu-west-3"      = "Z3Q77PNBQS71R4"
  "eu-north-1"     = "Z23TAZ6LKFMNIO"
  "me-south-1"     = "ZS929ML54UICD"
  "sa-east-1"      = "Z2P70J7HTTTPLU"
}

$ALB_HOSTED_ZONE_ID = $ALB_REGION_HOSTED_ZONE_IDS[$AWS_REGION]
if (-not $ALB_HOSTED_ZONE_ID) {
  Write-Host "Warning: No ALB hosted zone ID found for region $AWS_REGION. Using a default value."
  $ALB_HOSTED_ZONE_ID = "Z32O12XQLNTSW2" # Default to eu-west-1
}

Write-Host "Using ALB hosted zone ID: $ALB_HOSTED_ZONE_ID"
Write-Host "Using ALB DNS name: $ALB_DNS_NAME"

# Validate ALB DNS name before creating record
if ([string]::IsNullOrWhiteSpace($ALB_DNS_NAME)) {
  Write-Host "Error: ALB DNS name is empty. Cannot create Route 53 record."
  Write-Host "Please ensure the ALB was created successfully and has a valid DNS name."
  exit 1
}

# Create the A record for the subdomain
$changeBatchJson = @"
{
  "Comment": "Create A record alias for $($env:SUBDOMAIN).$($env:DOMAIN_NAME)",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$($env:SUBDOMAIN).$($env:DOMAIN_NAME)",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$($env:ALB_HOSTED_ZONE_ID)", # <-- Use correct variable
          "DNSName": "$($env:ALB_DNS_NAME)",
          "EvaluateTargetHealth": $true
        }
      }
    }
  ]
}
"@

# Save the change batch to a temporary file
$tempChangeBatchFile = Join-Path -Path $ScriptDir -ChildPath "route53-change.json"
$changeBatchJson | Out-File -FilePath $tempChangeBatchFile -Encoding utf8

# Apply the Route 53 change
$route53Command = "aws route53 change-resource-record-sets --hosted-zone-id $HOSTED_ZONE_ID --change-batch file://$tempChangeBatchFile --region $env:AWS_REGION"
Invoke-AWSCommand -Command $route53Command

# Remove temporary file
Remove-Item -Path $tempChangeBatchFile

Write-Host "Created/Updated Route 53 record for $($env:SUBDOMAIN).$($env:DOMAIN_NAME)"

Write-Host "Route 53 record creation completed" 
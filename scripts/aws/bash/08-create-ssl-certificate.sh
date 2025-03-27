#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source all the configuration files
source "$SCRIPT_DIR/01-setup-variables.sh"

echo "Checking/Creating SSL certificate..."

# Construct domain names for certificate check
WILDCARD_DOMAIN="*.${DOMAIN_NAME}"
ROOT_DOMAIN="${DOMAIN_NAME}"

# Check for existing valid certificate
echo "Checking for existing certificate for ${ROOT_DOMAIN} and ${WILDCARD_DOMAIN}..."
CERTIFICATE_ARN=$(aws acm list-certificates --certificate-statuses ISSUED --region $AWS_REGION --output json | \
  jq -r --arg rootDomain "$ROOT_DOMAIN" --arg wildcardDomain "$WILDCARD_DOMAIN" \
  '.CertificateSummaryList[] | select(.DomainName == $rootDomain or .DomainName == $wildcardDomain) | .CertificateArn' | \
  head -n 1) # Take the first match if multiple exist

# If a valid certificate ARN is found, use it and skip creation
if [ -n "$CERTIFICATE_ARN" ]; then
  echo "Found existing valid certificate: $CERTIFICATE_ARN"
  
  # Verify it covers both root and wildcard (optional but good practice)
  CERT_DETAILS=$(aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region $AWS_REGION --output json)
  HAS_ROOT=$(echo $CERT_DETAILS | jq -r --arg rootDomain "$ROOT_DOMAIN" '.Certificate.SubjectAlternativeNames[]? | select(. == $rootDomain)')
  HAS_WILDCARD=$(echo $CERT_DETAILS | jq -r --arg wildcardDomain "$WILDCARD_DOMAIN" '.Certificate.SubjectAlternativeNames[]? | select(. == $wildcardDomain)')
  
  if [[ -n "$HAS_ROOT" && -n "$HAS_WILDCARD" ]]; then
      echo "Existing certificate covers both root and wildcard domains."
  else
      # If it doesn't cover both, you might still want to proceed or handle differently
      echo "Warning: Existing certificate $CERTIFICATE_ARN found, but it might not cover both ${ROOT_DOMAIN} and ${WILDCARD_DOMAIN}."
      # Decide if you want to exit or continue using the found certificate
      # exit 1 # Uncomment to exit if specific coverage is required
  fi
  
else
  echo "No existing valid certificate found. Requesting a new one..."
  # Request a new certificate
  CERTIFICATE_ARN=$(aws acm request-certificate \
    --domain-name $DOMAIN_NAME \
    --subject-alternative-names "*.${DOMAIN_NAME}" \
    --validation-method DNS \
    --query 'CertificateArn' \
    --output text \
    --region $AWS_REGION)

  if [ $? -ne 0 ] || [ -z "$CERTIFICATE_ARN" ]; then
    echo "Failed to request certificate"
    exit 1
  fi

  echo "Requested certificate ARN: $CERTIFICATE_ARN"
  echo "Waiting for certificate validation details..."
  sleep 10 # Give ACM time to populate validation options

  # Get validation options (this might need retry logic in a robust script)
  VALIDATION_OPTIONS=$(aws acm describe-certificate \
    --certificate-arn $CERTIFICATE_ARN \
    --query 'Certificate.DomainValidationOptions' \
    --output json \
    --region $AWS_REGION)

  if [ -z "$VALIDATION_OPTIONS" ] || [ "$VALIDATION_OPTIONS" == "[]" ]; then
      echo "Failed to retrieve validation options for certificate $CERTIFICATE_ARN. Please check the ACM console."
      exit 1
  fi
  
  echo "Certificate validation options retrieved."

  # --- Add DNS validation records ---
  # Get Hosted Zone ID for the domain
  HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
      --dns-name $DOMAIN_NAME \
      --query 'HostedZones[0].Id' \
      --output text \
      --region $AWS_REGION)
      
  if [ -z "$HOSTED_ZONE_ID" ]; then
      echo "Error: Hosted Zone ID for $DOMAIN_NAME not found."
      exit 1
  fi
  
  echo "Using Hosted Zone ID: $HOSTED_ZONE_ID"
  
  CHANGE_BATCH_FILE="$SCRIPT_DIR/acm-validation-records.json"
  echo '{ "Changes": [' > $CHANGE_BATCH_FILE
  
  FIRST=true
  # Loop through validation options and create CNAME records
  echo $VALIDATION_OPTIONS | jq -c '.[]' | while read -r option; do
      RECORD_NAME=$(echo $option | jq -r '.ResourceRecord.Name')
      RECORD_VALUE=$(echo $option | jq -r '.ResourceRecord.Value')
      RECORD_TYPE=$(echo $option | jq -r '.ResourceRecord.Type')

      if [ "$RECORD_TYPE" == "CNAME" ]; then
          if [ "$FIRST" = false ]; then
              echo ',' >> $CHANGE_BATCH_FILE
          fi
          
          cat >> $CHANGE_BATCH_FILE << EOF
          {
              "Action": "UPSERT",
              "ResourceRecordSet": {
                  "Name": "$RECORD_NAME",
                  "Type": "$RECORD_TYPE",
                  "TTL": 300,
                  "ResourceRecords": [{ "Value": "$RECORD_VALUE" }]
              }
          }
EOF
          FIRST=false
          echo "Prepared validation record for $RECORD_NAME"
      fi
  done
  
  echo '] }' >> $CHANGE_BATCH_FILE

  # Apply DNS changes if any records were prepared
  if [ "$FIRST" = false ]; then
      echo "Applying DNS validation records..."
      aws route53 change-resource-record-sets \
          --hosted-zone-id $HOSTED_ZONE_ID \
          --change-batch file://$CHANGE_BATCH_FILE \
          --region $AWS_REGION
      if [ $? -ne 0 ]; then
          echo "Failed to apply DNS validation records."
          rm $CHANGE_BATCH_FILE # Clean up
          exit 1
      fi
      echo "DNS validation records submitted. Waiting for validation..."
      rm $CHANGE_BATCH_FILE # Clean up
  else
      echo "No CNAME validation records found to apply."
      rm $CHANGE_BATCH_FILE # Clean up
      # Consider exiting if validation relies on CNAME records
      # exit 1
  fi

  # Wait for the certificate to be validated
  echo "Waiting for certificate validation to complete... This can take several minutes."
  aws acm wait certificate-validated \
    --certificate-arn $CERTIFICATE_ARN \
    --region $AWS_REGION

  if [ $? -ne 0 ]; then
    echo "Certificate validation failed or timed out."
    exit 1
  fi

  echo "Certificate validation successful!"
fi # End of check for existing certificate

# Save certificate ARN to a file
cat > "$SCRIPT_DIR/certificate-config.sh" << EOF
#!/bin/bash

# Certificate Configuration
export CERTIFICATE_ARN=$CERTIFICATE_ARN
EOF

chmod +x "$SCRIPT_DIR/certificate-config.sh"

echo "Certificate configuration saved to $SCRIPT_DIR/certificate-config.sh"
echo "SSL certificate setup completed" 
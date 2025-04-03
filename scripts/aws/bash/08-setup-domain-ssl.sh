#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"

# Source configuration
source "$SCRIPT_DIR/01-setup-variables.sh"

# Source hosted zone config if exists
if [ -f "$CONFIG_DIR/route53-config.sh" ]; then
    source "$CONFIG_DIR/route53-config.sh"
fi

echo "Setting up Domain, SSL Certificate, and DNS Record..."

# --- Validate Inputs ---
if [ -z "$DOMAIN_NAME" ]; then echo "Error: DOMAIN_NAME is not set."; exit 1; fi
if [ -z "$SUBDOMAIN" ]; then echo "Error: SUBDOMAIN is not set."; exit 1; fi
if [ -z "$AWS_REGION" ]; then echo "Error: AWS_REGION is not set."; exit 1; fi

# Check for HOSTED_ZONE_ID (should have been set by 02b-create-hosted-zone.sh)
if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "Error: HOSTED_ZONE_ID is not set."
    echo "Ensure script '02b-create-hosted-zone.sh' ran successfully and exported the variable."
    exit 1
else
     echo "Using HOSTED_ZONE_ID from environment: $HOSTED_ZONE_ID"
fi

# Use your existing certificate if specified manually
EXISTING_CERTIFICATE_ARN="arn:aws:acm:eu-west-1:765194364851:certificate/acb20d41-9500-4aa3-a1ce-bf799f909eb7"

# --- Check/Create SSL Certificate --- 
WILDCARD_DOMAIN="*.${DOMAIN_NAME}"
ROOT_DOMAIN="${DOMAIN_NAME}"

echo "Checking for existing valid SSL certificate for ${ROOT_DOMAIN} and ${WILDCARD_DOMAIN}..."

# First, check if we have the specific ARN available
if [ -n "$EXISTING_CERTIFICATE_ARN" ]; then
    echo "Using provided certificate ARN: $EXISTING_CERTIFICATE_ARN"
    CERT_STATUS=$(aws acm describe-certificate --certificate-arn "$EXISTING_CERTIFICATE_ARN" --query 'Certificate.Status' --output text --region $AWS_REGION 2>/dev/null)
    
    if [ "$CERT_STATUS" == "ISSUED" ]; then
        echo "Certificate is valid and issued."
        CERTIFICATE_ARN=$EXISTING_CERTIFICATE_ARN
    else
        echo "Warning: Provided certificate is not in ISSUED state (Status: $CERT_STATUS). Will search for another valid certificate."
    fi
fi

# If no valid certificate found yet, search for any valid certificates
if [ -z "$CERTIFICATE_ARN" ]; then
    # Get all certificates
    ALL_CERTIFICATES=$(aws acm list-certificates --certificate-statuses ISSUED --region $AWS_REGION --output json)
    
    # Try to find a certificate for our domain
    echo "Searching for valid certificates for $ROOT_DOMAIN or $WILDCARD_DOMAIN..."
    
    # First look for the wildcard cert (preferred)
    CERTIFICATE_ARN=$(echo "$ALL_CERTIFICATES" | jq -r --arg domain "$WILDCARD_DOMAIN" '.CertificateSummaryList[] | select(.DomainName == $domain) | .CertificateArn' | head -n 1)
    
    # If no wildcard cert, look for root domain cert
    if [ -z "$CERTIFICATE_ARN" ]; then
        CERTIFICATE_ARN=$(echo "$ALL_CERTIFICATES" | jq -r --arg domain "$ROOT_DOMAIN" '.CertificateSummaryList[] | select(.DomainName == $domain) | .CertificateArn' | head -n 1)
    fi
    
    # If still no cert, check for subjAltNames (more comprehensive check)
    if [ -z "$CERTIFICATE_ARN" ]; then
        echo "No primary domain match found, checking subject alternative names..."
        
        CERT_ARNS=$(echo "$ALL_CERTIFICATES" | jq -r '.CertificateSummaryList[].CertificateArn')
        for ARN in $CERT_ARNS; do
            CERT_DETAILS=$(aws acm describe-certificate --certificate-arn "$ARN" --region $AWS_REGION --output json)
            
            # Check if our domains are in the SAN list
            ROOT_IN_SANS=$(echo "$CERT_DETAILS" | jq -r --arg domain "$ROOT_DOMAIN" '.Certificate.SubjectAlternativeNames[] | select(. == $domain)' | wc -l)
            WILD_IN_SANS=$(echo "$CERT_DETAILS" | jq -r --arg domain "$WILDCARD_DOMAIN" '.Certificate.SubjectAlternativeNames[] | select(. == $domain)' | wc -l)
            
            if [ "$ROOT_IN_SANS" -gt 0 ] || [ "$WILD_IN_SANS" -gt 0 ]; then
                CERTIFICATE_ARN="$ARN"
                echo "Found certificate with matching subject alternative names: $CERTIFICATE_ARN"
                break
            fi
        done
    fi
fi

if [ -n "$CERTIFICATE_ARN" ]; then
    echo "Found existing valid certificate: $CERTIFICATE_ARN"
    # Verify it covers both domains
    CERT_DETAILS=$(aws acm describe-certificate --certificate-arn "$CERTIFICATE_ARN" --region $AWS_REGION --output json)
    ROOT_COVERED=$(echo "$CERT_DETAILS" | jq -r --arg domain "$ROOT_DOMAIN" '.Certificate.DomainName == $domain or (.Certificate.SubjectAlternativeNames[] | select(. == $domain)) | length > 0' 2>/dev/null)
    WILD_COVERED=$(echo "$CERT_DETAILS" | jq -r --arg domain "$WILDCARD_DOMAIN" '.Certificate.DomainName == $domain or (.Certificate.SubjectAlternativeNames[] | select(. == $domain)) | length > 0' 2>/dev/null)
    
    if [ "$ROOT_COVERED" != "true" ] || [ "$WILD_COVERED" != "true" ]; then
        echo "Warning: Existing certificate may not cover both $ROOT_DOMAIN and $WILDCARD_DOMAIN."
        echo "Certificate details: "
        echo "$CERT_DETAILS" | jq '.Certificate.DomainName, .Certificate.SubjectAlternativeNames'
        echo "Will use it anyway as it's in ISSUED state."
    fi
else
    echo "No existing valid certificate found. Requesting a new one..."
    CERTIFICATE_ARN=$(aws acm request-certificate \
      --domain-name $ROOT_DOMAIN \
      --subject-alternative-names $WILDCARD_DOMAIN \
      --validation-method DNS \
      --query 'CertificateArn' \
      --output text \
      --region $AWS_REGION)

    if [ $? -ne 0 ] || [ -z "$CERTIFICATE_ARN" ]; then echo "Failed to request certificate"; exit 1; fi
    echo "Requested certificate ARN: $CERTIFICATE_ARN"
    echo "Waiting for certificate validation details... (up to 60s)"
    
    # --- Add DNS validation records --- 
    MAX_RETRIES=6
    RETRY_DELAY=10
    RETRY_COUNT=0
    VALIDATION_OPTIONS=""

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
      VALIDATION_OPTIONS=$(aws acm describe-certificate \
        --certificate-arn $CERTIFICATE_ARN \
        --query 'Certificate.DomainValidationOptions' \
        --output json \
        --region $AWS_REGION 2>/dev/null)
      
      # Check if options are populated and contain ResourceRecord
      if [[ -n "$VALIDATION_OPTIONS" && "$VALIDATION_OPTIONS" != "[]" && $(echo $VALIDATION_OPTIONS | jq 'map(has("ResourceRecord")) | all') == "true" ]]; then
        echo "Validation options retrieved successfully."
        break
      fi
      RETRY_COUNT=$((RETRY_COUNT + 1))
      echo "Validation options not ready yet. Retrying in $RETRY_DELAY seconds... (Attempt $RETRY_COUNT/$MAX_RETRIES)"
      sleep $RETRY_DELAY
    done

    if [[ -z "$VALIDATION_OPTIONS" || "$VALIDATION_OPTIONS" == "[]" || $(echo $VALIDATION_OPTIONS | jq 'map(has("ResourceRecord")) | all') != "true" ]]; then
      echo "Error: Failed to retrieve valid validation options for certificate $CERTIFICATE_ARN after $MAX_RETRIES attempts."
      echo "Please check the ACM console."
      exit 1
    fi
    
    CHANGE_BATCH_RECORDS=()
    echo "Preparing DNS validation records..."
    echo $VALIDATION_OPTIONS | jq -c '.[]' | while read -r option; do
        RECORD_NAME=$(echo $option | jq -r '.ResourceRecord.Name')
        RECORD_VALUE=$(echo $option | jq -r '.ResourceRecord.Value')
        RECORD_TYPE=$(echo $option | jq -r '.ResourceRecord.Type')

        if [ "$RECORD_TYPE" == "CNAME" ]; then
            # Use jq to create a valid JSON object string for this change
            JSON_CHANGE=$(jq -n --arg name "$RECORD_NAME" --arg value "$RECORD_VALUE" '
              {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                  "Name": $name,
                  "Type": "CNAME",
                  "TTL": 300,
                  "ResourceRecords": [ { "Value": $value } ]
                }
              }')
            CHANGE_BATCH_RECORDS+=("$JSON_CHANGE")
            echo "Prepared CNAME record JSON for $RECORD_NAME"
        else
             echo "Skipping non-CNAME validation record type: $RECORD_TYPE for $RECORD_NAME"
        fi
    done
    
    # Construct the final JSON change batch using jq
    if [ ${#CHANGE_BATCH_RECORDS[@]} -gt 0 ]; then
        # Combine the JSON strings in the array into a single JSON array string
        COMBINED_CHANGES=$(IFS=,; echo "${CHANGE_BATCH_RECORDS[*]}")
        # Use jq to create the final ChangeBatch structure
        CHANGE_BATCH_JSON=$(jq -n --argjson changes "[$COMBINED_CHANGES]" '{ "Changes": $changes }')

        if [ -z "$CHANGE_BATCH_JSON" ] || [ "$CHANGE_BATCH_JSON" == "null" ]; then
            echo "Error: Failed to construct final Change Batch JSON using jq."
            exit 1
        fi
        
        echo "Final Change Batch JSON prepared:"
        echo $CHANGE_BATCH_JSON | jq . # Pretty print for verification

        echo "Applying DNS validation records..."
        # Use process substitution to avoid temporary file on Windows
        CHANGE_INFO=$(aws route53 change-resource-record-sets \
            --hosted-zone-id $HOSTED_ZONE_ID \
            --change-batch "$CHANGE_BATCH_JSON" \
            --region $AWS_REGION \
            --query 'ChangeInfo.Id' --output text)
            
        if [ $? -ne 0 ]; then echo "Failed to submit DNS validation records."; exit 1; fi
        echo "DNS validation records submitted (Change ID: $CHANGE_INFO). Waiting for sync..."
        aws route53 wait resource-record-sets-changed --id $CHANGE_INFO --region $AWS_REGION
        echo "DNS records synced. Waiting for ACM validation..."
    else
        echo "No CNAME validation records needed or prepared."
    fi

    # Wait for the certificate to be validated
    echo "Waiting for certificate validation to complete... This can take several minutes."
    aws acm wait certificate-validated --certificate-arn $CERTIFICATE_ARN --region $AWS_REGION
    if [ $? -ne 0 ]; then echo "Certificate validation failed or timed out."; exit 1; fi
    echo "Certificate validation successful!"
fi

# Save certificate ARN to certificate-config.sh
CERTIFICATE_CONFIG_FILE="$CONFIG_DIR/certificate-config.sh"
if [ -n "$CERTIFICATE_ARN" ]; then
    echo "#!/bin/bash" > "$CERTIFICATE_CONFIG_FILE"
    echo "# Certificate Configuration" >> "$CERTIFICATE_CONFIG_FILE"
    echo "export CERTIFICATE_ARN=\"$CERTIFICATE_ARN\"" >> "$CERTIFICATE_CONFIG_FILE"
    chmod +x "$CERTIFICATE_CONFIG_FILE"
    echo "Certificate ARN saved to $CERTIFICATE_CONFIG_FILE"
else
    echo "Error: Certificate ARN is empty after check/creation process."
    exit 1
fi

# --- Route 53 Record Creation REMOVED ---
# This section has been moved to 09b-create-dns-record.sh

echo "Domain/SSL Certificate setup completed."
# Note: Final DNS record pointing to ALB will be created in a later step. 
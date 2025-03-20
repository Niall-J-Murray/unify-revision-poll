#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"

echo "Creating SSL certificate and Route 53 records..."

# Request a certificate for the domain
CERTIFICATE_ARN=$(aws acm request-certificate \
  --domain-name ${SUBDOMAIN}.${DOMAIN_NAME} \
  --validation-method DNS \
  --query 'CertificateArn' \
  --output text \
  --region $AWS_REGION)

echo "Requested certificate: $CERTIFICATE_ARN"

# Wait a bit for the certificate to be processed
echo "Waiting for certificate to be processed..."
sleep 10

# Get the DNS validation records
VALIDATION_OUTPUT=$(aws acm describe-certificate \
  --certificate-arn $CERTIFICATE_ARN \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --region $AWS_REGION)

VALIDATION_NAME=$(echo $VALIDATION_OUTPUT | jq -r '.Name')
VALIDATION_VALUE=$(echo $VALIDATION_OUTPUT | jq -r '.Value')

echo "Certificate validation name: $VALIDATION_NAME"
echo "Certificate validation value: $VALIDATION_VALUE"

# Get the hosted zone ID for the domain
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name $DOMAIN_NAME \
  --query 'HostedZones[0].Id' \
  --output text)

if [ -z "$HOSTED_ZONE_ID" ] || [ "$HOSTED_ZONE_ID" == "None" ]; then
  echo "No hosted zone found for $DOMAIN_NAME. You need to set up Route 53 for your domain first."
  exit 1
fi

echo "Found hosted zone: $HOSTED_ZONE_ID"

# Create the DNS validation record
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [
      {
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "'$VALIDATION_NAME'",
          "Type": "CNAME",
          "TTL": 300,
          "ResourceRecords": [
            {
              "Value": "'$VALIDATION_VALUE'"
            }
          ]
        }
      }
    ]
  }' \
  --region $AWS_REGION

echo "Created DNS validation record"

# Wait for the certificate to be validated
echo "Waiting for certificate validation (this may take up to 30 minutes)..."
echo "You can continue with the next steps while this is in progress."

# Save certificate configuration to a file
cat > "$SCRIPT_DIR/certificate-config.sh" << EOF
#!/bin/bash

# Certificate Configuration
export CERTIFICATE_ARN=$CERTIFICATE_ARN
export HOSTED_ZONE_ID=$HOSTED_ZONE_ID
EOF

chmod +x "$SCRIPT_DIR/certificate-config.sh"

echo "Certificate configuration saved to $SCRIPT_DIR/certificate-config.sh"
echo "SSL certificate creation completed" 
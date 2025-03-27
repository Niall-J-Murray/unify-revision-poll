#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source all the configuration files
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$SCRIPT_DIR/certificate-config.sh"
source "$SCRIPT_DIR/alb-config.sh"

echo "Creating Route 53 record..."

# Get the hosted zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name $DOMAIN_NAME \
  --query 'HostedZones[0].Id' \
  --output text \
  --region $AWS_REGION)

if [ -z "$HOSTED_ZONE_ID" ]; then
  echo "No hosted zone found for domain: $DOMAIN_NAME"
  echo "Please create a hosted zone in Route 53 first"
  exit 1
fi

echo "Found hosted zone ID: $HOSTED_ZONE_ID"

# Create the A record for the subdomain
if [ -z "$ALB_HOSTED_ZONE_ID" ]; then
    echo "Error: ALB Canonical Hosted Zone ID not found in alb-config.sh. Cannot create Route 53 alias."
    exit 1
fi

cat > "$SCRIPT_DIR/route53-change.json" << EOF
{
  "Comment": "Create A record alias for ${SUBDOMAIN}.${DOMAIN_NAME}",
  "Changes": [
    {
      "Action": "UPSERT", # Use UPSERT to avoid errors if record already exists
      "ResourceRecordSet": {
        "Name": "${SUBDOMAIN}.${DOMAIN_NAME}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${ALB_HOSTED_ZONE_ID}", # <-- Use the correct variable
          "DNSName": "${ALB_DNS_NAME}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

# Apply the Route 53 change
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch file://"$SCRIPT_DIR/route53-change.json" \
  --region $AWS_REGION

echo "Created Route 53 record for ${SUBDOMAIN}.${DOMAIN_NAME}"
echo "Route 53 record creation completed" 
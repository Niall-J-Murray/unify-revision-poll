#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$SCRIPT_DIR/certificate-config.sh"
source "$SCRIPT_DIR/alb-config.sh"

echo "Creating Route 53 record for the application..."

# Determine the Hosted Zone ID for the ALB
# For eu-west-1 (Ireland), the ALB Hosted Zone ID is Z32O12XQLNTSW2
# For a complete list, see https://docs.aws.amazon.com/general/latest/gr/elb.html
ALB_HOSTED_ZONE_ID="Z32O12XQLNTSW2"

# Create Route 53 record set for the subdomain
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [
      {
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "'${SUBDOMAIN}'.'${DOMAIN_NAME}'",
          "Type": "A",
          "AliasTarget": {
            "HostedZoneId": "'$ALB_HOSTED_ZONE_ID'",
            "DNSName": "'$ALB_DNS_NAME'",
            "EvaluateTargetHealth": true
          }
        }
      }
    ]
  }' \
  --region $AWS_REGION

echo "Created Route 53 A record for ${SUBDOMAIN}.${DOMAIN_NAME} pointing to ALB"

# Create CNAME record for www
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [
      {
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "www.'${SUBDOMAIN}'.'${DOMAIN_NAME}'",
          "Type": "CNAME",
          "TTL": 300,
          "ResourceRecords": [
            {
              "Value": "'${SUBDOMAIN}'.'${DOMAIN_NAME}'"
            }
          ]
        }
      }
    ]
  }' \
  --region $AWS_REGION

echo "Created Route 53 CNAME record for www.${SUBDOMAIN}.${DOMAIN_NAME}"
echo "Route 53 records creation completed" 
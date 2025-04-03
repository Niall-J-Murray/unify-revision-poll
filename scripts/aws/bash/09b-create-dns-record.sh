#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"

echo "Creating Route 53 DNS Record..."

# Source necessary configuration
source "$SCRIPT_DIR/01-setup-variables.sh"
if [ -f "$CONFIG_DIR/alb-config.sh" ]; then
    source "$CONFIG_DIR/alb-config.sh"
else
    echo "Error: ALB configuration file ($CONFIG_DIR/alb-config.sh) not found."
    echo "Ensure '09-create-ecs-resources.sh' ran successfully."
    exit 1
fi

# HOSTED_ZONE_ID is needed. Try sourcing from 01-setup first, then check if empty.
# Note: 08-setup-domain-ssl.sh should have already found/validated it.
if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "Error: HOSTED_ZONE_ID is empty. Script '08-setup-domain-ssl.sh' might not have run or failed to find the Zone ID."
    exit 1
fi

# Validate required variables from sourced files
if [ -z "$SUBDOMAIN" ]; then echo "Error: SUBDOMAIN is not set."; exit 1; fi
if [ -z "$DOMAIN_NAME" ]; then echo "Error: DOMAIN_NAME is not set."; exit 1; fi
if [ -z "$ALB_DNS_NAME" ]; then echo "Error: ALB_DNS_NAME is not set."; exit 1; fi
if [ -z "$ALB_HOSTED_ZONE_ID" ]; then echo "Error: ALB_HOSTED_ZONE_ID is not set."; exit 1; fi
if [ -z "$AWS_REGION" ]; then echo "Error: AWS_REGION is not set."; exit 1; fi

# --- Create Route 53 A Record ---
TARGET_RECORD_NAME="${SUBDOMAIN}.${DOMAIN_NAME}"
echo "Checking/Creating Route 53 A record for ${TARGET_RECORD_NAME} pointing to ALB ${ALB_DNS_NAME}..."

# First check if the record already exists
echo "Checking for existing DNS record..."
EXISTING_RECORD=$(aws route53 list-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --query "ResourceRecordSets[?Name=='${TARGET_RECORD_NAME}.']" \
  --output json \
  --region $AWS_REGION)

if [ -n "$EXISTING_RECORD" ] && [ "$EXISTING_RECORD" != "[]" ]; then
    # Check if it's an alias record pointing to our ALB
    IS_ALIAS=$(echo "$EXISTING_RECORD" | jq -r ".[0].AliasTarget != null")
    if [ "$IS_ALIAS" == "true" ]; then
        CURRENT_ALB_DNS=$(echo "$EXISTING_RECORD" | jq -r ".[0].AliasTarget.DNSName")
        # Remove trailing dot if exists for comparison
        CURRENT_ALB_DNS=${CURRENT_ALB_DNS%.}
        ALB_DNS_NAME=${ALB_DNS_NAME%.}
        
        if [ "$CURRENT_ALB_DNS" == "$ALB_DNS_NAME" ]; then
            echo "DNS record for ${TARGET_RECORD_NAME} already exists and points to the correct ALB. No changes needed."
            exit 0
        else
            echo "DNS record exists but points to a different ALB. Will update to point to the current ALB."
            # Continue to update the record
        fi
    else
        echo "DNS record exists but is not an alias record. Will update to correct type."
        # Continue to update the record
    fi
else
    echo "No existing DNS record found. Will create a new one."
fi

# Construct the change batch for Route 53
# Use jq to create JSON safely, handling potential special characters
ROUTE53_CHANGE_JSON=$(jq -n --arg recordName "$TARGET_RECORD_NAME" --arg albDnsName "$ALB_DNS_NAME" --arg albHostedZoneId "$ALB_HOSTED_ZONE_ID" '{
  "Comment": "Create/Update A record alias for \($recordName) pointing to ALB",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": $recordName,
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": $albHostedZoneId,
          "DNSName": $albDnsName,
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}')

if [ -z "$ROUTE53_CHANGE_JSON" ]; then
    echo "Error: Failed to construct Route 53 change batch JSON."
    exit 1
fi

echo "Applying Route 53 change..."
CHANGE_INFO=$(aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch "$ROUTE53_CHANGE_JSON" \
  --region $AWS_REGION \
  --query 'ChangeInfo.Id' --output text)

if [ $? -ne 0 ]; then echo "Failed to submit Route 53 record change."; exit 1; fi
echo "Route 53 record change submitted (Change ID: $CHANGE_INFO). Waiting for sync..."
aws route53 wait resource-record-sets-changed --id $CHANGE_INFO --region $AWS_REGION

echo "Route 53 record created/updated for ${TARGET_RECORD_NAME}"
echo "DNS Record creation completed." 
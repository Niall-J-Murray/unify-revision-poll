#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"

echo "Checking/Creating Route 53 Public Hosted Zone..."

# Source necessary configuration
source "$SCRIPT_DIR/01-setup-variables.sh"

# Validate required variables
if [ -z "$DOMAIN_NAME" ]; then echo "Error: DOMAIN_NAME is not set in 01-setup-variables.sh."; exit 1; fi
if [ -z "$AWS_REGION" ]; then echo "Error: AWS_REGION is not set."; exit 1; fi
if [ -z "$APP_NAME" ]; then echo "Error: APP_NAME is not set."; exit 1; fi

# Check if HOSTED_ZONE_ID is already set (e.g., manually in 01-setup or env var)
if [ -n "$HOSTED_ZONE_ID" ]; then
    echo "INFO: HOSTED_ZONE_ID is already set to '$HOSTED_ZONE_ID'. Skipping check/creation."
    # Optional: Verify it actually exists in AWS?
    aws route53 get-hosted-zone --id $HOSTED_ZONE_ID --region $AWS_REGION > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Warning: Pre-set HOSTED_ZONE_ID '$HOSTED_ZONE_ID' not found or not accessible."
        # Continue anyway, subsequent steps will likely fail if ID is wrong.
    fi
    exit 0
fi

echo "Attempting to find existing Hosted Zone for $DOMAIN_NAME..."
HZ_INFO=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_NAME." --max-items 1 --query "HostedZones[?Name==\"$DOMAIN_NAME.\"]" --output json --region $AWS_REGION 2>/dev/null)

if [ -n "$HZ_INFO" ] && [ "$HZ_INFO" != "[]" ]; then
    # Hosted Zone Found
    echo "Found existing Hosted Zone for $DOMAIN_NAME."
    HOSTED_ZONE_ID=$(echo "$HZ_INFO" | jq -r '.[0].Id' | sed 's|/hostedzone/||')
    echo "Exporting HOSTED_ZONE_ID=$HOSTED_ZONE_ID"
    export HOSTED_ZONE_ID # Export for subsequent scripts in this session

    # Get Nameservers for existing zone
    NAMESERVERS=$(aws route53 get-hosted-zone --id $HOSTED_ZONE_ID --query 'DelegationSet.NameServers' --output json --region $AWS_REGION)
    echo "------------------------------------------------------------------"
    echo "INFO: Using Existing Hosted Zone: $HOSTED_ZONE_ID"
    echo "Ensure your domain registrar for '$DOMAIN_NAME' is using these AWS nameservers:"
    echo $NAMESERVERS | jq -r '.[]'
    echo "------------------------------------------------------------------"
else
    # Hosted Zone Not Found - Create it
    echo "Hosted Zone for $DOMAIN_NAME not found. Creating..."
    # Unique reference for idempotency
    CALLER_REF="$APP_NAME-$DOMAIN_NAME-create-$(date +%s)" # Add timestamp for potential retries
    
    # Capture stderr along with stdout
    CREATE_HZ_OUTPUT=$(aws route53 create-hosted-zone --name $DOMAIN_NAME --caller-reference $CALLER_REF --hosted-zone-config Comment="Created by $APP_NAME deployment script" --output json --region $AWS_REGION 2>&1)
    CREATE_HZ_EXIT_CODE=$?
    
    if [ $CREATE_HZ_EXIT_CODE -ne 0 ]; then
        # Check if the error is HostedZoneAlreadyExists
        if echo "$CREATE_HZ_OUTPUT" | grep -q 'HostedZoneAlreadyExists'; then
            echo "INFO: HostedZoneAlreadyExists error received. Zone likely exists but wasn't found initially."
            echo "Attempting to retrieve existing zone details again..."
            # Retry the list operation, assuming it might work now or permissions allow get
            HZ_INFO_RETRY=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_NAME." --max-items 1 --query "HostedZones[?Name==\"$DOMAIN_NAME.\"]" --output json --region $AWS_REGION 2>/dev/null)
            if [ -n "$HZ_INFO_RETRY" ] && [ "$HZ_INFO_RETRY" != "[]" ]; then
                echo "Successfully retrieved existing Hosted Zone details on retry."
                HOSTED_ZONE_ID=$(echo "$HZ_INFO_RETRY" | jq -r '.[0].Id' | sed 's|/hostedzone/||')
                NAMESERVERS=$(aws route53 get-hosted-zone --id $HOSTED_ZONE_ID --query 'DelegationSet.NameServers' --output json --region $AWS_REGION)
                echo "Exporting HOSTED_ZONE_ID=$HOSTED_ZONE_ID"
                export HOSTED_ZONE_ID # Export for subsequent scripts in this session
                echo "------------------------------------------------------------------"
                echo "INFO: Using Existing Hosted Zone: $HOSTED_ZONE_ID"
                echo "Ensure your domain registrar for '$DOMAIN_NAME' is using these AWS nameservers:"
                echo $NAMESERVERS | jq -r '.[]'
                echo "------------------------------------------------------------------"
            else
                echo "Error: Failed to retrieve existing zone details even after HostedZoneAlreadyExists error."
                echo "Please check Route 53 console and IAM permissions (route53:ListHostedZonesByName, route53:GetHostedZone)."
                exit 1
            fi
        else
            # A different error occurred during creation
            echo "Error: Failed to create Hosted Zone for $DOMAIN_NAME."
            echo "AWS Response: $CREATE_HZ_OUTPUT"
            exit 1
        fi
    else
        # Creation was successful (exit code 0)
        HOSTED_ZONE_ID=$(echo "$CREATE_HZ_OUTPUT" | jq -r '.HostedZone.Id' | sed 's|/hostedzone/||')
        NAMESERVERS=$(echo "$CREATE_HZ_OUTPUT" | jq -r '.DelegationSet.NameServers | @json') # Keep as JSON list initially
        
        echo "Successfully created Hosted Zone: $HOSTED_ZONE_ID"
        echo "Exporting HOSTED_ZONE_ID=$HOSTED_ZONE_ID"
        export HOSTED_ZONE_ID # Export for subsequent scripts in this session
        
        echo "========================= IMPORTANT MANUAL STEP ========================"
        echo "You MUST update the nameservers for your domain '$DOMAIN_NAME' at your domain registrar."
        echo "Replace the current nameservers with these four AWS nameservers:"
        echo " "
        echo $NAMESERVERS | jq -r '.[]' # Print each NS on a new line
        echo " "
        echo "DNS propagation can take time (minutes to hours). Subsequent steps"
        echo "(like ACM certificate validation) will fail if nameservers are not updated"
        echo "and propagated."
        echo "========================================================================"
        # Add a pause? Or just warn? Warning is better for potential automation.
        echo "Warning: Pausing for 30 seconds to allow reading nameserver instructions..."
        sleep 30
    fi
fi

echo "Hosted Zone check/creation complete." 
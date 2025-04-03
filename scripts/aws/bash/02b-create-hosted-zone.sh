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
    echo "INFO: HOSTED_ZONE_ID is already set to '$HOSTED_ZONE_ID'. Verifying it actually exists..."
    aws route53 get-hosted-zone --id $HOSTED_ZONE_ID --region $AWS_REGION > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Warning: Pre-set HOSTED_ZONE_ID '$HOSTED_ZONE_ID' not found or not accessible."
        echo "Will search for another valid hosted zone instead."
        HOSTED_ZONE_ID=""
    else
        echo "Verified: Hosted zone $HOSTED_ZONE_ID exists and is accessible."
        exit 0
    fi
fi

echo "Searching for existing Hosted Zone for $DOMAIN_NAME..."
# Get ALL hosted zones and filter for our domain
ALL_HOSTED_ZONES=$(aws route53 list-hosted-zones --output json --region $AWS_REGION 2>/dev/null)
if [ $? -ne 0 ]; then 
    echo "Error retrieving hosted zones. Check AWS CLI configuration and permissions."
    exit 1
fi

# Use a more robust approach to find ALL matching hosted zones
MATCHING_ZONES=$(echo "$ALL_HOSTED_ZONES" | jq -r --arg domain "$DOMAIN_NAME." '.HostedZones[] | select(.Name == $domain) | .Id')

if [ -n "$MATCHING_ZONES" ]; then
    ZONE_COUNT=$(echo "$MATCHING_ZONES" | wc -l)
    echo "Found $ZONE_COUNT hosted zone(s) matching $DOMAIN_NAME"
    
    # Use the first zone found
    HOSTED_ZONE_ID=$(echo "$MATCHING_ZONES" | head -n 1 | sed 's|/hostedzone/||')
    echo "Using hosted zone: $HOSTED_ZONE_ID"
    
    # Get Nameservers for existing zone
    NAMESERVERS=$(aws route53 get-hosted-zone --id $HOSTED_ZONE_ID --query 'DelegationSet.NameServers' --output json --region $AWS_REGION)
    echo "------------------------------------------------------------------"
    echo "INFO: Using Existing Hosted Zone: $HOSTED_ZONE_ID"
    echo "Ensure your domain registrar for '$DOMAIN_NAME' is using these AWS nameservers:"
    echo $NAMESERVERS | jq -r '.[]'
    echo "------------------------------------------------------------------"
    
    # Export HOSTED_ZONE_ID
    export HOSTED_ZONE_ID
    
    # Write to config file for other scripts to use
    ZONE_CONFIG_FILE="$CONFIG_DIR/route53-config.sh"
    echo "#!/bin/bash" > "$ZONE_CONFIG_FILE"
    echo "# Route 53 Hosted Zone Configuration" >> "$ZONE_CONFIG_FILE"
    echo "export HOSTED_ZONE_ID=\"$HOSTED_ZONE_ID\"" >> "$ZONE_CONFIG_FILE"
    chmod +x "$ZONE_CONFIG_FILE"
    echo "Hosted zone ID saved to $ZONE_CONFIG_FILE"
else
    # Hosted Zone Not Found - Create it
    echo "No hosted zone for $DOMAIN_NAME found. Creating..."
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
            # Retry the list operation
            ALL_HOSTED_ZONES=$(aws route53 list-hosted-zones --output json --region $AWS_REGION 2>/dev/null)
            MATCHING_ZONES=$(echo "$ALL_HOSTED_ZONES" | jq -r --arg domain "$DOMAIN_NAME." '.HostedZones[] | select(.Name == $domain) | .Id')
            
            if [ -n "$MATCHING_ZONES" ]; then
                HOSTED_ZONE_ID=$(echo "$MATCHING_ZONES" | head -n 1 | sed 's|/hostedzone/||')
                NAMESERVERS=$(aws route53 get-hosted-zone --id $HOSTED_ZONE_ID --query 'DelegationSet.NameServers' --output json --region $AWS_REGION)
                echo "Exporting HOSTED_ZONE_ID=$HOSTED_ZONE_ID"
                export HOSTED_ZONE_ID
                
                # Write to config file
                ZONE_CONFIG_FILE="$CONFIG_DIR/route53-config.sh"
                echo "#!/bin/bash" > "$ZONE_CONFIG_FILE"
                echo "# Route 53 Hosted Zone Configuration" >> "$ZONE_CONFIG_FILE"
                echo "export HOSTED_ZONE_ID=\"$HOSTED_ZONE_ID\"" >> "$ZONE_CONFIG_FILE"
                chmod +x "$ZONE_CONFIG_FILE"
                echo "Hosted zone ID saved to $ZONE_CONFIG_FILE"
                
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
        export HOSTED_ZONE_ID
        
        # Write to config file
        ZONE_CONFIG_FILE="$CONFIG_DIR/route53-config.sh"
        echo "#!/bin/bash" > "$ZONE_CONFIG_FILE"
        echo "# Route 53 Hosted Zone Configuration" >> "$ZONE_CONFIG_FILE"
        echo "export HOSTED_ZONE_ID=\"$HOSTED_ZONE_ID\"" >> "$ZONE_CONFIG_FILE"
        chmod +x "$ZONE_CONFIG_FILE"
        echo "Hosted zone ID saved to $ZONE_CONFIG_FILE"
        
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
        # Replace sleep with skippable read
        read -t 30 -p "Pausing for 30 seconds to allow reading nameserver instructions. Press Enter to skip..."
        echo "" # Add a newline after the read prompt
    fi
fi

echo "Hosted Zone check/creation complete." 
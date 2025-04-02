#!/bin/bash

# --- Check AWS CLI Version ---
echo "Checking AWS CLI version..."
aws --version
echo "--------------------------"

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
# Source RDS config safely
RDS_CONFIG_FILE="$CONFIG_DIR/rds-config.sh"
if [ -f "$RDS_CONFIG_FILE" ]; then
    source "$RDS_CONFIG_FILE"
else
    echo "Error: $RDS_CONFIG_FILE not found. Run 04-create-rds.sh first."
    exit 1
fi

echo "Creating/Updating SSM Parameters..."

# Construct DATABASE_URL and DIRECT_URL
if [ -z "$RDS_ENDPOINT" ]; then
    echo "Error: RDS_ENDPOINT not found in $RDS_CONFIG_FILE."
    exit 1
fi
# Ensure required DB variables are set for URL construction
if [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ] || [ -z "$DB_NAME" ]; then
 echo "Error: DB_USERNAME, DB_PASSWORD, or DB_NAME not set. Check 01-setup-variables.sh"
 exit 1
fi
DATABASE_URL="postgresql://${DB_USERNAME}:${DB_PASSWORD}@${RDS_ENDPOINT}:5432/${DB_NAME}?schema=public"
DIRECT_URL=$DATABASE_URL

# Construct App URL
if [ -z "$SUBDOMAIN" ] || [ -z "$DOMAIN_NAME" ]; then
 echo "Error: SUBDOMAIN or DOMAIN_NAME not set. Check 01-setup-variables.sh"
 exit 1
fi
APP_URL="https://${SUBDOMAIN}.${DOMAIN_NAME}"

# Generate NEXTAUTH_SECRET if not set in environment
if [ -z "$NEXTAUTH_SECRET" ]; then
    echo "Generating NEXTAUTH_SECRET..."
    NEXTAUTH_SECRET=$(openssl rand -hex 32)
fi

# Check essential variables needed for parameters
if [ -z "$APP_NAME" ]; then echo "Error: APP_NAME is not set."; exit 1; fi

# Define parameter name prefix (using hyphens)
PARAM_NAME_PREFIX="${APP_NAME}"

# Function to put/update a parameter
put_parameter() {
    local name_suffix=$1 # e.g., DATABASE_URL
    local value=$2
    local type=${3:-"SecureString"} # Default to SecureString
    local param_name="${PARAM_NAME_PREFIX}-${name_suffix}" # e.g., feature-poll-DATABASE_URL

    echo "Putting parameter: $param_name"
    # Using Standard tier for simplicity. Add logic for Intelligent-Tiering if large values expected.
    aws ssm put-parameter --name "$param_name" --value "$value" --type "$type" --overwrite --region "$AWS_REGION"
    if [ $? -ne 0 ]; then echo "Failed to put parameter $param_name"; exit 1; fi
}

# Put parameters 
put_parameter "DATABASE_URL" "$DATABASE_URL" "SecureString"
put_parameter "DIRECT_URL" "$DIRECT_URL" "SecureString"
put_parameter "NEXT_PUBLIC_APP_URL" "$APP_URL" "String"
put_parameter "NEXTAUTH_URL" "$APP_URL" "String"
put_parameter "NEXTAUTH_SECRET" "$NEXTAUTH_SECRET" "SecureString"

# Parameters with defaults
EMAIL_SERVER_HOST_VALUE=${EMAIL_SERVER_HOST:-"YOUR_SMTP_HOST"}
EMAIL_SERVER_PORT_VALUE=${EMAIL_SERVER_PORT:-"587"}
EMAIL_SERVER_USER_VALUE=${EMAIL_SERVER_USER:-"YOUR_SMTP_USER"}
EMAIL_SERVER_PASSWORD_VALUE=${EMAIL_SERVER_PASSWORD:-"YOUR_SMTP_PASSWORD"}
EMAIL_FROM_VALUE=${EMAIL_FROM:-"noreply@${DOMAIN_NAME}"}
GOOGLE_CLIENT_ID_VALUE=${GOOGLE_CLIENT_ID:-"YOUR_GOOGLE_CLIENT_ID"}
GOOGLE_CLIENT_SECRET_VALUE=${GOOGLE_CLIENT_SECRET:-"YOUR_GOOGLE_CLIENT_SECRET"}
GITHUB_ID_VALUE=${GITHUB_ID:-"YOUR_GITHUB_ID"}
GITHUB_SECRET_VALUE=${GITHUB_SECRET:-"YOUR_GITHUB_SECRET"}

put_parameter "EMAIL_SERVER_HOST" "$EMAIL_SERVER_HOST_VALUE" "String"
put_parameter "EMAIL_SERVER_PORT" "$EMAIL_SERVER_PORT_VALUE" "String"
put_parameter "EMAIL_SERVER_USER" "$EMAIL_SERVER_USER_VALUE" "String"
put_parameter "EMAIL_SERVER_PASSWORD" "$EMAIL_SERVER_PASSWORD_VALUE" "SecureString"
put_parameter "EMAIL_FROM" "$EMAIL_FROM_VALUE" "String"
put_parameter "GOOGLE_CLIENT_ID" "$GOOGLE_CLIENT_ID_VALUE" "SecureString"
put_parameter "GOOGLE_CLIENT_SECRET" "$GOOGLE_CLIENT_SECRET_VALUE" "SecureString"
put_parameter "GITHUB_ID" "$GITHUB_ID_VALUE" "SecureString"
put_parameter "GITHUB_SECRET" "$GITHUB_SECRET_VALUE" "SecureString"
put_parameter "NODE_ENV" "production" "String"

# --- FINAL ATTEMPT 2: Simplest write to secrets-config.sh ---
SECRETS_CONFIG_FILE="$CONFIG_DIR/secrets-config.sh"
PARAM_NAME_PREFIX="${APP_NAME}"
SSM_POLICY_ARN_FOUND="" # Initialize

# Try to find SSM Policy ARN
SSM_POLICY_ARN_FOUND=$(aws iam list-policies --scope Local --query "Policies[?PolicyName==\`${APP_NAME}-ssm-parameter-access-policy\`].Arn" --output text --region $AWS_REGION 2>/dev/null)

echo "Writing final config to $SECRETS_CONFIG_FILE..."

# Overwrite the file completely using heredoc
cat > "$SECRETS_CONFIG_FILE" <<- EOF
#!/bin/bash
# Secrets Configuration

export SECRET_PARAMETER_NAME_PREFIX="$PARAM_NAME_PREFIX"

# SSM Policy ARN (if found)
export SSM_POLICY_ARN="${SSM_POLICY_ARN_FOUND:-# NOT FOUND}"

EOF

# Make executable
chmod +x "$SECRETS_CONFIG_FILE"
echo "Finished writing $SECRETS_CONFIG_FILE"
# --- END FINAL ATTEMPT 2 ---

echo "SSM Parameter setup completed."

# Reminder about optional secrets
echo ""
echo "INFO: Placeholders used for optional secrets (Email, Google, Github)."
echo "      If you intend to use these features, update the parameters in AWS SSM"
echo "      or set the corresponding environment variables before running this script:"
echo "      EMAIL_SERVER_HOST, EMAIL_SERVER_PORT, EMAIL_SERVER_USER, EMAIL_SERVER_PASSWORD, EMAIL_FROM"
echo "      GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GITHUB_ID, GITHUB_SECRET"

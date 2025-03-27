#!/bin/bash

# --- Check AWS CLI Version ---
echo "Checking AWS CLI version..."
aws --version
echo "--------------------------"

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$SCRIPT_DIR/rds-config.sh"

echo "Creating/Updating SSM Parameters..."

# Construct DATABASE_URL and DIRECT_URL
# Ensure RDS_ENDPOINT is available from rds-config.sh
if [ -z "$RDS_ENDPOINT" ]; then
    echo "Error: RDS_ENDPOINT not found in rds-config.sh"
    exit 1
fi
DATABASE_URL="postgresql://${DB_USERNAME}:${DB_PASSWORD}@${RDS_ENDPOINT}:5432/${DB_NAME}?schema=public"
DIRECT_URL=$DATABASE_URL # Often the same for Prisma Migrate

# Construct App URL
APP_URL="https://${SUBDOMAIN}.${DOMAIN_NAME}"

# Generate NEXTAUTH_SECRET if not provided
if [ -z "$NEXTAUTH_SECRET" ]; then
    echo "Generating NEXTAUTH_SECRET..."
    NEXTAUTH_SECRET=$(openssl rand -hex 32)
fi

# Define parameter name prefix (using hyphens instead of slashes)
# Ensure APP_NAME is set
if [ -z "$APP_NAME" ]; then
    echo "Error: APP_NAME environment variable is not set."
    exit 1
fi
# --- Use hyphens as delimiter ---
PARAM_NAME_PREFIX="${APP_NAME}" # Just the app name

# Function to put/update a parameter
put_parameter() {
    local name_suffix=$1 # e.g., DATABASE_URL
    local value=$2
    local type=${3:-"SecureString"}
    # Construct the full parameter name using a hyphen
    local param_name_raw="${PARAM_NAME_PREFIX}-${name_suffix}" # e.g., feature-poll-DATABASE_URL

    # --- Aggressive Cleaning: Keep only printable ASCII characters ---
    local param_name=$(echo "$param_name_raw" | tr -dc '[:print:]')

    # --- Debugging ---
    echo "-------------------------------------"
    echo "DEBUG: Putting Parameter"
    echo "DEBUG:   Name Suffix: '$name_suffix'"
    echo "DEBUG:   Name Prefix: '$PARAM_NAME_PREFIX'"
    echo "DEBUG:   Raw Name   : '$param_name_raw'"
    echo "DEBUG:   Clean Name : '$param_name'" # Check the hyphenated name
    echo "DEBUG:   Type       : '$type'"
    echo "DEBUG:   Region     : '$AWS_REGION'"
    # echo "DEBUG:   Value      : '$value'"
    echo "-------------------------------------"
    # --- End Debugging ---

    # Basic validation after cleaning (allow hyphens)
    if [[ ! "$param_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        echo "Error: Cleaned parameter name '$param_name' still looks invalid after cleaning."
        exit 1
    fi

    echo "Putting parameter: $param_name"
    # Put the entire command on a single line
    aws ssm put-parameter --name "$param_name" --value "$value" --type "$type" --overwrite --region "$AWS_REGION"

    if [ $? -ne 0 ]; then echo "Failed to put parameter $param_name"; exit 1; fi
}

# Put parameters (use SecureString for sensitive values)
put_parameter "DATABASE_URL" "$DATABASE_URL" "SecureString"
put_parameter "DIRECT_URL" "$DIRECT_URL" "SecureString"
put_parameter "NEXT_PUBLIC_APP_URL" "$APP_URL" "String"
put_parameter "NEXTAUTH_URL" "$APP_URL" "String"
put_parameter "NEXTAUTH_SECRET" "$NEXTAUTH_SECRET" "SecureString"
put_parameter "EMAIL_SERVER_HOST" "${EMAIL_SERVER_HOST:-smtp.example.com}" "String"
put_parameter "EMAIL_SERVER_PORT" "${EMAIL_SERVER_PORT:-587}" "String"
put_parameter "EMAIL_SERVER_USER" "${EMAIL_SERVER_USER:-user@example.com}" "String"
put_parameter "EMAIL_SERVER_PASSWORD" "${EMAIL_SERVER_PASSWORD:-your_email_password}" "SecureString"
put_parameter "EMAIL_FROM" "${EMAIL_FROM:-noreply@${DOMAIN_NAME}}" "String"
put_parameter "GOOGLE_CLIENT_ID" "${GOOGLE_CLIENT_ID:-your_google_client_id}" "SecureString"
put_parameter "GOOGLE_CLIENT_SECRET" "${GOOGLE_CLIENT_SECRET:-your_google_client_secret}" "SecureString"
put_parameter "GITHUB_ID" "${GITHUB_ID:-your_github_id}" "SecureString"
put_parameter "GITHUB_SECRET" "${GITHUB_SECRET:-your_github_secret}" "SecureString"
put_parameter "NODE_ENV" "production" "String"

# Save the parameter name prefix for potential use (though individual names are needed for task def)
cat > "$SCRIPT_DIR/secrets-config.sh" << EOF
#!/bin/bash
# SSM Parameter Name Prefix (using hyphens)
export SECRET_PARAMETER_NAME_PREFIX="$PARAM_NAME_PREFIX"
EOF
chmod +x "$SCRIPT_DIR/secrets-config.sh"

echo "SSM Parameter configuration saved to $SCRIPT_DIR/secrets-config.sh"
echo "SSM Parameter setup completed." 
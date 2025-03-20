#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$SCRIPT_DIR/rds-config.sh"

echo "Creating secrets for environment variables..."

# Create a secret with all the environment variables
SECRET_NAME="${APP_NAME}-env-vars"

# Extract values from .env and .env.local files
if [ -f "$PROJECT_ROOT/.env.local" ]; then
    NEXTAUTH_SECRET=$(grep NEXTAUTH_SECRET "$PROJECT_ROOT/.env.local" | cut -d "=" -f2 | tr -d "\"' " || echo "")
    EMAIL_SERVER_HOST=$(grep EMAIL_SERVER_HOST "$PROJECT_ROOT/.env.local" | cut -d "=" -f2 | tr -d "\"' " || echo "")
    EMAIL_SERVER_PORT=$(grep EMAIL_SERVER_PORT "$PROJECT_ROOT/.env.local" | cut -d "=" -f2 | tr -d "\"' " || echo "")
    EMAIL_SERVER_USER=$(grep EMAIL_SERVER_USER "$PROJECT_ROOT/.env.local" | cut -d "=" -f2 | tr -d "\"' " || echo "")
    EMAIL_SERVER_PASSWORD=$(grep EMAIL_SERVER_PASSWORD "$PROJECT_ROOT/.env.local" | cut -d "=" -f2 | tr -d "\"' " || echo "")
    EMAIL_FROM=$(grep EMAIL_FROM "$PROJECT_ROOT/.env.local" | cut -d "=" -f2 | tr -d "\"' " || echo "")
    GOOGLE_CLIENT_ID=$(grep GOOGLE_CLIENT_ID "$PROJECT_ROOT/.env.local" | cut -d "=" -f2 | tr -d "\"' " || echo "")
    GOOGLE_CLIENT_SECRET=$(grep GOOGLE_CLIENT_SECRET "$PROJECT_ROOT/.env.local" | cut -d "=" -f2 | tr -d "\"' " || echo "")
    GITHUB_ID=$(grep GITHUB_ID "$PROJECT_ROOT/.env.local" | cut -d "=" -f2 | tr -d "\"' " || echo "")
    GITHUB_SECRET=$(grep GITHUB_SECRET "$PROJECT_ROOT/.env.local" | cut -d "=" -f2 | tr -d "\"' " || echo "")
else
    echo "Warning: .env.local file not found. Using empty values for some secrets."
    NEXTAUTH_SECRET=""
    EMAIL_SERVER_HOST=""
    EMAIL_SERVER_PORT=""
    EMAIL_SERVER_USER=""
    EMAIL_SERVER_PASSWORD=""
    EMAIL_FROM=""
    GOOGLE_CLIENT_ID=""
    GOOGLE_CLIENT_SECRET=""
    GITHUB_ID=""
    GITHUB_SECRET=""
fi

# Create a JSON string with the environment variables
ENV_JSON=$(cat << EOF
{
  "DATABASE_URL": "postgresql://$DB_USERNAME:$DB_PASSWORD@$DB_ENDPOINT:$DB_PORT/$DB_NAME?schema=public&pool_max=5",
  "DIRECT_URL": "postgresql://$DB_USERNAME:$DB_PASSWORD@$DB_ENDPOINT:$DB_PORT/$DB_NAME",
  "NEXT_PUBLIC_APP_URL": "https://${SUBDOMAIN}.${DOMAIN_NAME}",
  "NEXTAUTH_URL": "https://${SUBDOMAIN}.${DOMAIN_NAME}",
  "NEXTAUTH_SECRET": "$NEXTAUTH_SECRET",
  "EMAIL_SERVER_HOST": "$EMAIL_SERVER_HOST",
  "EMAIL_SERVER_PORT": "$EMAIL_SERVER_PORT",
  "EMAIL_SERVER_USER": "$EMAIL_SERVER_USER",
  "EMAIL_SERVER_PASSWORD": "$EMAIL_SERVER_PASSWORD",
  "EMAIL_FROM": "$EMAIL_FROM",
  "GOOGLE_CLIENT_ID": "$GOOGLE_CLIENT_ID",
  "GOOGLE_CLIENT_SECRET": "$GOOGLE_CLIENT_SECRET",
  "GITHUB_ID": "$GITHUB_ID",
  "GITHUB_SECRET": "$GITHUB_SECRET",
  "NODE_ENV": "production"
}
EOF
)

# Create the secret
aws secretsmanager create-secret \
  --name $SECRET_NAME \
  --description "Environment variables for ${APP_NAME}" \
  --secret-string "$ENV_JSON" \
  --region $AWS_REGION

echo "Created secret with environment variables: $SECRET_NAME"

# Get the secret ARN
SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id $SECRET_NAME \
  --query 'ARN' \
  --output text \
  --region $AWS_REGION)

# Save secrets configuration to a file
cat > "$SCRIPT_DIR/secrets-config.sh" << EOF
#!/bin/bash

# Secrets Configuration
export SECRET_NAME=$SECRET_NAME
export SECRET_ARN=$SECRET_ARN
EOF

chmod +x "$SCRIPT_DIR/secrets-config.sh"

echo "Secrets configuration saved to $SCRIPT_DIR/secrets-config.sh"
echo "Secrets creation completed" 
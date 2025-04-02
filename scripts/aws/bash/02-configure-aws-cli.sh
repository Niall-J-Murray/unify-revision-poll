#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"

echo "Configuring AWS CLI Profile (if needed)..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# --- Deprecated Credential Setting ---
# WARNING: Setting credentials via environment variables passed to 'aws configure set' 
#          is generally discouraged for security reasons.
#
# Recommended Alternatives:
# 1. IAM Roles for EC2/ECS: If running scripts from AWS compute, use IAM roles.
#    The CLI will automatically pick up credentials.
# 2. AWS Credentials File (~/.aws/credentials): Use 'aws configure' interactively 
#    or manually edit the credentials file to set up a profile.
#    Example: 
#    aws configure --profile $APP_NAME 
#    (Then ensure AWS_PROFILE=$APP_NAME is set when running scripts)
# 3. AWS SSO / IAM Identity Center: Use temporary credentials obtained via SSO.
#
# This script will now only set the default region and output format for the 
# default profile, assuming credentials are provided through other means.
# --- End Deprecated Credential Setting ---

# Configure default region and output format
aws configure set default.region "$AWS_REGION"
aws configure set default.output json

# Optionally, set for a specific profile if AWS_PROFILE is defined
# if [ -n "$AWS_PROFILE" ]; then
#    echo "Configuring profile: $AWS_PROFILE"
#    aws configure set profile.$AWS_PROFILE.region "$AWS_REGION"
#    aws configure set profile.$AWS_PROFILE.output json
# fi

echo "AWS CLI default region/output configuration check complete!"
echo "Please ensure AWS credentials are configured securely (e.g., via IAM role, ~/.aws/credentials, or SSO)." 
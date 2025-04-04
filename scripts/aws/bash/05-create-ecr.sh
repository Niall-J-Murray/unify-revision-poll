#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"
# Config files should exist from previous step, no need to mkdir -p here

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"

echo "Creating ECR repository..."

ECR_REPOSITORY_NAME="${APP_NAME}-repo"

echo "Checking for existing ECR repository: $ECR_REPOSITORY_NAME..."
REPOSITORY_URI=$(aws ecr describe-repositories --repository-names $ECR_REPOSITORY_NAME --query 'repositories[0].repositoryUri' --output text --region $AWS_REGION 2>/dev/null)

if [ $? -eq 0 ]; then
    echo "Found existing ECR repository: $REPOSITORY_URI"
else
    echo "ECR repository $ECR_REPOSITORY_NAME not found. Creating..."
    REPOSITORY_URI=$(aws ecr create-repository \
      --repository-name $ECR_REPOSITORY_NAME \
      --image-scanning-configuration scanOnPush=true \
      --image-tag-mutability IMMUTABLE \
      --region $AWS_REGION \
      --tags Key=AppName,Value=$APP_NAME \
      --query 'repository.repositoryUri' \
      --output text)

    if [ $? -ne 0 ] || [ -z "$REPOSITORY_URI" ]; then
        echo "Error: Failed to create ECR repository $ECR_REPOSITORY_NAME"
        exit 1
    fi
    echo "Created ECR repository: $REPOSITORY_URI"
fi

# Save ECR configuration to a file
ECR_CONFIG_FILE="$CONFIG_DIR/ecr-config.sh"
cat > "$ECR_CONFIG_FILE" << EOF
#!/bin/bash

# ECR Configuration
export REPOSITORY_URI=$REPOSITORY_URI
EOF

chmod +x "$ECR_CONFIG_FILE"

echo "ECR configuration saved to $ECR_CONFIG_FILE"
echo "ECR repository creation completed!" 
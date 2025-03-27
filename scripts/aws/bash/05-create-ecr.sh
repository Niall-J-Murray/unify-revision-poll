#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"

echo "Creating ECR repository..."

# Check if repository exists
REPOSITORY_EXISTS=$(aws ecr describe-repositories \
  --repository-names $ECR_REPOSITORY_NAME \
  --query 'repositories[0].repositoryName' \
  --output text 2>/dev/null || echo "")

if [ -z "$REPOSITORY_EXISTS" ]; then
  # Create repository
  aws ecr create-repository \
    --repository-name $ECR_REPOSITORY_NAME \
    --image-scanning-configuration scanOnPush=true \
    --image-tag-mutability MUTABLE

  echo "Created ECR repository: $ECR_REPOSITORY_NAME"
else
  echo "Repository already exists: $ECR_REPOSITORY_NAME"
fi

# Get repository URI
REPOSITORY_URI=$(aws ecr describe-repositories \
  --repository-names $ECR_REPOSITORY_NAME \
  --query 'repositories[0].repositoryUri' \
  --output text)

echo "Repository URI: $REPOSITORY_URI"

# Save ECR configuration to a file
cat > "$SCRIPT_DIR/ecr-config.sh" << EOF
#!/bin/bash

# ECR Configuration
export REPOSITORY_URI=$REPOSITORY_URI
EOF

chmod +x "$SCRIPT_DIR/ecr-config.sh"

echo "ECR configuration saved to $SCRIPT_DIR/ecr-config.sh"
echo "ECR repository creation completed!" 
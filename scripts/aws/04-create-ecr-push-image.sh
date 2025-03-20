#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"

echo "Creating ECR repository and pushing Docker image..."

# Create ECR repository
aws ecr create-repository \
  --repository-name $ECR_REPO_NAME \
  --image-scanning-configuration scanOnPush=true \
  --region $AWS_REGION

echo "Created ECR repository: $ECR_REPO_NAME"

# Get ECR login password and login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.$AWS_REGION.amazonaws.com

# Change to project root directory
cd "$PROJECT_ROOT"

# Build Docker image
echo "Building Docker image..."
docker build -t $ECR_REPO_NAME .

echo "Built Docker image"

# Tag the image
ECR_REPO_URI=$(aws ecr describe-repositories \
  --repository-names $ECR_REPO_NAME \
  --query 'repositories[0].repositoryUri' \
  --output text \
  --region $AWS_REGION)

docker tag $ECR_REPO_NAME:latest $ECR_REPO_URI:latest

echo "Tagged Docker image: $ECR_REPO_URI:latest"

# Push the image to ECR
echo "Pushing Docker image to ECR..."
docker push $ECR_REPO_URI:latest

echo "Pushed Docker image to ECR"

# Save ECR configuration to a file
cat > "$SCRIPT_DIR/ecr-config.sh" << EOF
#!/bin/bash

# ECR Configuration
export ECR_REPO_URI=$ECR_REPO_URI
EOF

chmod +x "$SCRIPT_DIR/ecr-config.sh"

echo "ECR configuration saved to $SCRIPT_DIR/ecr-config.sh"
echo "ECR repository creation and image push completed" 
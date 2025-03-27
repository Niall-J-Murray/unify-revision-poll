#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$SCRIPT_DIR/ecr-config.sh"

echo "Building and pushing Docker image..."

# Build the Docker image
docker build -t $ECR_REPOSITORY_NAME:latest "$PROJECT_ROOT"

# Tag the image
docker tag $ECR_REPOSITORY_NAME:latest $REPOSITORY_URI:latest

# Get ECR login token and login to Docker
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REPOSITORY_URI

# Push the image to ECR
docker push $REPOSITORY_URI:latest

echo "Docker image pushed successfully!" 
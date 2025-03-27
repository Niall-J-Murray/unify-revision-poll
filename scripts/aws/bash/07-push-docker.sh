#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# --- Correct path to project root (go up three levels) ---
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../../.." && pwd )"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$SCRIPT_DIR/ecr-config.sh"

echo "Building and pushing Docker image..."

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REPOSITORY_URI
if [ $? -ne 0 ]; then echo "ECR login failed"; exit 1; fi

# --- Change to Project Root Directory ---
echo "Changing directory to $PROJECT_ROOT"
cd "$PROJECT_ROOT"
if [ $? -ne 0 ]; then echo "Failed to change directory to project root"; exit 1; fi

# Build the Docker image from the current directory (.)
# Dockerfile should be found automatically in the context (.)
echo "Running docker build from context: $(pwd)"
docker build -t $ECR_REPOSITORY_NAME:latest . # Use '.' as context
if [ $? -ne 0 ]; then echo "Docker build failed"; exit 1; fi

# --- Optional: Change back to original directory if needed ---
# cd "$SCRIPT_DIR"

# Tag the image
docker tag $ECR_REPOSITORY_NAME:latest $REPOSITORY_URI:latest
if [ $? -ne 0 ]; then echo "Docker tag failed"; exit 1; fi

# Push the image to ECR
docker push $REPOSITORY_URI:latest
if [ $? -ne 0 ]; then echo "Docker push failed"; exit 1; fi

echo "Docker image pushed successfully!" 
#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# --- Correct path to project root (go up three levels) ---
PROJECT_ROOT="$( cd "$SCRIPT_DIR/../../.." && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"

# Source the variables
source "$SCRIPT_DIR/01-setup-variables.sh"
source "$CONFIG_DIR/ecr-config.sh"

echo "Building and pushing Docker image..."

# Check if ECR repository URI is set
if [ -z "$REPOSITORY_URI" ]; then
    echo "Error: REPOSITORY_URI is not set. Please run 05-create-ecr.sh first."
    exit 1
fi

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REPOSITORY_URI
if [ $? -ne 0 ]; then echo "ECR login failed"; exit 1; fi

# --- Generate a Unique Tag ---
UNIQUE_TAG=$(date +'%Y%m%d-%H%M%S')
echo "Using unique image tag: $UNIQUE_TAG"

# --- Change to Project Root Directory ---
echo "Changing directory to $PROJECT_ROOT"
cd "$PROJECT_ROOT"
if [ $? -ne 0 ]; then echo "Failed to change directory to project root"; exit 1; fi

# --- Verify Dockerfile exists ---
if [ ! -f Dockerfile ]; then
    echo "Error: Dockerfile not found in project root ($PROJECT_ROOT)."
    exit 1
fi
echo "Dockerfile found."

# Build the Docker image from the current directory (.), tagging directly with unique tag
IMAGE_URI_WITH_TAG="${REPOSITORY_URI}:${UNIQUE_TAG}"
echo "Running docker build --no-cache -t $IMAGE_URI_WITH_TAG from context: $(pwd)"
docker build --no-cache -t $IMAGE_URI_WITH_TAG .
if [ $? -ne 0 ]; then echo "Docker build failed"; exit 1; fi

# Push the uniquely tagged image to ECR
echo "Pushing image: $IMAGE_URI_WITH_TAG"
docker push $IMAGE_URI_WITH_TAG
if [ $? -ne 0 ]; then echo "Docker push failed"; exit 1; fi

# --- Save the successfully pushed tag to config ---
ECR_CONFIG_FILE="$CONFIG_DIR/ecr-config.sh"
echo "Updating $ECR_CONFIG_FILE with latest pushed tag..."
# Overwrite file robustly
cat > "$ECR_CONFIG_FILE" << EOF
#!/bin/bash
# ECR Configuration
export REPOSITORY_URI="$REPOSITORY_URI"
export LATEST_PUSHED_TAG="$UNIQUE_TAG"
EOF
chmod +x "$ECR_CONFIG_FILE"
echo "Successfully pushed and recorded tag: $UNIQUE_TAG"

# Change back to the script directory (good practice)
cd "$SCRIPT_DIR"

echo "Docker image built and pushed successfully!" 
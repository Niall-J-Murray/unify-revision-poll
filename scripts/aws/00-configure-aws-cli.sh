#!/bin/bash

echo "==============================================================="
echo "AWS CLI Configuration"
echo "==============================================================="
echo ""
echo "This script will help you configure AWS CLI with your credentials."
echo "You'll need your AWS Access Key ID and Secret Access Key."
echo ""

# Check if AWS CLI is installed
aws --version > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "AWS CLI is not installed. Please install it first."
    echo "For Windows: Run 'winget install -e --id Amazon.AWSCLI' in PowerShell"
    echo "For Linux: Run 'curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\" && unzip awscliv2.zip && sudo ./aws/install'"
    exit 1
fi

echo "AWS CLI is installed."
echo ""

# Read AWS credentials
read -p "Enter your AWS Access Key ID: " aws_access_key_id
read -p "Enter your AWS Secret Access Key: " aws_secret_access_key
read -p "Enter your default region name [eu-west-1]: " aws_region
aws_region=${aws_region:-eu-west-1}
read -p "Enter your default output format [json]: " aws_output
aws_output=${aws_output:-json}

# Configure AWS CLI
echo "Configuring AWS CLI..."
aws configure set aws.access_key_id "$aws_access_key_id"
aws configure set aws.secret_access_key "$aws_secret_access_key"
aws configure set default.region "$aws_region"
aws configure set default.output "$aws_output"

# Detect OS and set up SSL certificates if needed
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
    echo "Windows environment detected. Setting up SSL certificates..."
    
    # Create AWS CLI directory if it doesn't exist
    mkdir -p ~/.aws

    # Check if curl is available
    if command -v curl &> /dev/null; then
        echo "Downloading Amazon Trust Services root certificates..."
        curl -o ~/.aws/ca-bundle.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem
        
        # Set the CA bundle path
        aws configure set default.ca_bundle ~/.aws/ca-bundle.pem
        echo "SSL certificate bundle configured."
    else
        echo "Warning: curl is not available. Unable to download SSL certificates."
        echo "You may need to manually download the Amazon Trust Services certificates from:"
        echo "https://www.amazontrust.com/repository/AmazonRootCA1.pem"
        echo "and save it to ~/.aws/ca-bundle.pem"
    fi
fi

# Verify the configuration
echo "Verifying AWS configuration..."
aws sts get-caller-identity

if [ $? -eq 0 ]; then
    echo "AWS CLI configuration completed successfully."
else
    echo "There was an issue with the AWS CLI configuration."
    echo "Please check your credentials and try again."
    exit 1
fi

echo ""
echo "AWS CLI configuration verified successfully."
echo "Your AWS account is ready for deployment."
echo "===============================================================" 
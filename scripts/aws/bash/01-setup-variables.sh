#!/bin/bash

# --- Essential Variable Checks ---
# Ensure AWS Region is set (already exported below, but good practice to check if sourced elsewhere)
if [ -z "$AWS_REGION" ]; then
    export AWS_REGION="eu-west-1" # Default if not set
    echo "Warning: AWS_REGION not set, defaulting to $AWS_REGION"
fi

# HOSTED_ZONE_ID check removed - Script 08 will handle dynamic lookup or fail if needed.

# --- End Essential Variable Checks ---

# AWS Configuration
export AWS_REGION="eu-west-1"
export APP_NAME="feature-poll"
export DOMAIN_NAME="murrdev.com"
export SUBDOMAIN="feature-poll"

# Database Configuration
export DB_NAME="feature_poll"
export DB_USERNAME="dbadmin"
export DB_PASSWORD="$(openssl rand -hex 32)"  # Changed from base64 to hex
export DB_INSTANCE_CLASS="db.t3.micro"
export DB_ENGINE="postgres"
export DB_ENGINE_VERSION="16"
export DB_ALLOCATED_STORAGE="20"

# --- New: Bastion Configuration ---
export BASTION_INSTANCE_TYPE="t3.micro" # Or t4g.micro if using ARM AMI
# Note: BASTION_KEY_PAIR_NAME and YOUR_PUBLIC_IP_CIDR still need manual edit in 04b-setup-bastion.sh

# VPC Configuration
export VPC_CIDR="10.0.0.0/16"
export PUBLIC_SUBNET_1_CIDR="10.0.1.0/24"
export PUBLIC_SUBNET_2_CIDR="10.0.2.0/24"
export PRIVATE_SUBNET_1_CIDR="10.0.3.0/24"
export PRIVATE_SUBNET_2_CIDR="10.0.4.0/24"

# ECR Configuration
export ECR_REPOSITORY_NAME="${APP_NAME}-repo"

# ECS Configuration
export ECS_CLUSTER_NAME="${APP_NAME}-cluster"
export ECS_SERVICE_NAME="${APP_NAME}-service"
export ECS_TASK_FAMILY="${APP_NAME}-task"
export ECS_CONTAINER_NAME="${APP_NAME}-container"
export ECS_TASK_CPU=256
export ECS_TASK_MEMORY=512
export ECS_CONTAINER_PORT=3000
export ECS_SERVICE_COUNT=1

# Load Balancer Configuration
export ALB_NAME="${APP_NAME}-alb"
export ALB_TG_NAME="${APP_NAME}-tg"

# SSL Configuration - Your existing certificate ARN
export SSL_CERTIFICATE_ARN="arn:aws:acm:eu-west-1:765194364851:certificate/acb20d41-9500-4aa3-a1ce-bf799f909eb7"

# Source config files if they exist
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_DIR="$SCRIPT_DIR/config"
mkdir -p "$CONFIG_DIR"

# Source hosted zone ID if available
if [ -f "$CONFIG_DIR/route53-config.sh" ]; then
    source "$CONFIG_DIR/route53-config.sh"
fi

# Source certificate ARN if available (will override default if script has been run before)
if [ -f "$CONFIG_DIR/certificate-config.sh" ]; then
    source "$CONFIG_DIR/certificate-config.sh"
fi

# Export all variables
set -a 

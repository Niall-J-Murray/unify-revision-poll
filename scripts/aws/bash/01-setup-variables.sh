#!/bin/bash

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

# SSL Configuration
export SSL_CERTIFICATE_ARN=""
export HOSTED_ZONE_ID=""

# Export all variables
set -a 
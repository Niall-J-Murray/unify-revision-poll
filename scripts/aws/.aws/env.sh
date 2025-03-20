#!/bin/bash

# AWS Region
export AWS_REGION="eu-west-1"

# Application name
export APP_NAME="unify-revision-poll"

# VPC and network settings
export VPC_CIDR="10.0.0.0/16"
export PUBLIC_SUBNET_1_CIDR="10.0.1.0/24"
export PUBLIC_SUBNET_2_CIDR="10.0.2.0/24"
export PRIVATE_SUBNET_1_CIDR="10.0.3.0/24"
export PRIVATE_SUBNET_2_CIDR="10.0.4.0/24"

# Domain settings
export DOMAIN_NAME="niallmurray.me"
export SUBDOMAIN="revision-poll"

# Database settings
export DB_NAME="revisionpoll"
export DB_USERNAME="revisionpoll_admin"
export DB_PASSWORD="RWy638K81PBNNvYZMokJKg=="
export DB_PORT="5432"
export DB_INSTANCE_CLASS="db.t3.micro"
export DB_ALLOCATED_STORAGE="20"

# ECS settings
export ECS_TASK_CPU="256"
export ECS_TASK_MEMORY="512"
export ECS_CONTAINER_PORT="3000"
export ECS_SERVICE_COUNT="1"

# ECR repository name
export ECR_REPO_NAME="unify-revision-poll"

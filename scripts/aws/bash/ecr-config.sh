#!/bin/bash

# ECR Configuration
export ECR_REPO_NAME="${APP_NAME}-repo"
export ECR_REPO_URI=""
export ECR_REPO_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPushPull",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
      ],
      "Resource": "*"
    }
  ]
}'

# ECS Configuration
export ECS_CLUSTER_NAME="${APP_NAME}-cluster"
export ECS_SERVICE_NAME="${APP_NAME}-service"
export ECS_TASK_FAMILY="${APP_NAME}"
export ECS_TASK_CPU="256"
export ECS_TASK_MEMORY="512"
export ECS_CONTAINER_PORT="3000"
export ECS_SERVICE_COUNT="1"
export ECS_CONTAINER_NAME="${APP_NAME}"
export ECS_CONTAINER_IMAGE="${ECR_REPO_URI}:latest"
export ECS_CONTAINER_MEMORY="512"
export ECS_CONTAINER_CPU="256"
export ECS_CONTAINER_ESSENTIAL="true"
export ECS_CONTAINER_LOG_DRIVER="awslogs"
export ECS_CONTAINER_LOG_OPTIONS="awslogs-group=/ecs/${APP_NAME},awslogs-region=${AWS_REGION},awslogs-stream-prefix=ecs"
export ECS_CONTAINER_HEALTH_CHECK_COMMAND="CMD-SHELL,wget -q -O - http://localhost:${ECS_CONTAINER_PORT}/api/health || exit 1"
export ECS_CONTAINER_HEALTH_CHECK_INTERVAL="30"
export ECS_CONTAINER_HEALTH_CHECK_TIMEOUT="5"
export ECS_CONTAINER_HEALTH_CHECK_RETRIES="3"
export ECS_CONTAINER_HEALTH_CHECK_START_PERIOD="60" 
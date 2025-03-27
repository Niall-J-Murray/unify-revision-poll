# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source all the configuration files
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\ecr-config.ps1"

Write-Host "Updating ECS task definition with correct ECR repository URI..."
Write-Host "ECR Repository URI: $ECR_REPO_URI"

# Create task definition with simple environment variables
Write-Host "Creating task definition..."
$containerDef = @{
    name             = $APP_NAME
    image            = "$ECR_REPO_URI`:latest"
    essential        = $true
    portMappings     = @(
        @{
            containerPort = [int]$ECS_CONTAINER_PORT
            hostPort      = [int]$ECS_CONTAINER_PORT
            protocol      = "tcp"
        }
    )
    logConfiguration = @{
        logDriver = "awslogs"
        options   = @{
            "awslogs-group"         = "/ecs/$APP_NAME"
            "awslogs-region"        = $AWS_REGION
            "awslogs-stream-prefix" = "ecs"
            "awslogs-create-group"  = "true"
        }
    }
    environment      = @(
        @{
            name  = "DATABASE_URL"
            value = "dummy-db-url"
        },
        @{
            name  = "DIRECT_URL"
            value = "dummy-direct-url"
        },
        @{
            name  = "NEXT_PUBLIC_APP_URL"
            value = "http://localhost:3000"
        },
        @{
            name  = "NEXTAUTH_URL"
            value = "http://localhost:3000"
        },
        @{
            name  = "NEXTAUTH_SECRET"
            value = "dummy-secret"
        },
        @{
            name  = "NODE_ENV"
            value = "production"
        }
    )
    healthCheck      = @{
        command     = @(
            "CMD-SHELL",
            "wget -q -O - http://localhost:$ECS_CONTAINER_PORT/api/health || exit 1"
        )
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
    }
}

$taskDef = @{
    family                  = $APP_NAME
    networkMode             = "awsvpc"
    executionRoleArn        = "arn:aws:iam::765194364851:role/${APP_NAME}-ecs-execution-role"
    requiresCompatibilities = @("FARGATE")
    cpu                     = $ECS_TASK_CPU
    memory                  = $ECS_TASK_MEMORY
    containerDefinitions    = @($containerDef)
}

$taskDefJson = ConvertTo-Json -Depth 10 -Compress $taskDef
$taskDefJson | Out-File -FilePath "$ScriptDir\task-definition.json" -Encoding ASCII -NoNewline
Write-Host "Created task definition file"

# Wait for file to be written
Start-Sleep -Seconds 2

# Register task definition
try {
    Write-Host "Registering task definition..."
    $TASK_DEFINITION_ARN = (aws ecs register-task-definition `
            --cli-input-json file://"$ScriptDir\task-definition.json" `
            --query 'taskDefinition.taskDefinitionArn' `
            --output text `
            --region $AWS_REGION)
  
    if ($TASK_DEFINITION_ARN -and $TASK_DEFINITION_ARN -ne "None") {
        Write-Host "Registered task definition: $TASK_DEFINITION_ARN"
    }
    else {
        throw "Failed to register task definition. Empty ARN returned."
    }
}
catch {
    Write-Host "Failed to register task definition: $_"
    exit 1
}

# Update service to use new task definition
try {
    Write-Host "Updating ECS service with new task definition..."
    aws ecs update-service `
        --cluster ${APP_NAME}-cluster `
        --service ${APP_NAME}-service `
        --task-definition $TASK_DEFINITION_ARN `
        --force-new-deployment `
        --region $AWS_REGION
  
    Write-Host "ECS service updated successfully. New tasks will use the updated image reference."
    Write-Host "Run the 09-finalize-deployment.ps1 script to complete the deployment."
}
catch {
    Write-Host "Failed to update ECS service: $_"
    exit 1
}

# Clean up temporary files
Remove-Item -Path "$ScriptDir\task-definition.json" -ErrorAction SilentlyContinue 
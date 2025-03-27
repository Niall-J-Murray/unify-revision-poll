# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source all the configuration files
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\vpc-config.ps1"
. "$ScriptDir\rds-config.ps1"
. "$ScriptDir\ecr-config.ps1"
. "$ScriptDir\certificate-config.ps1"
. "$ScriptDir\secrets-config.ps1"
. "$ScriptDir\alb-config.ps1"

Write-Host "Finalizing deployment..."

# Wait for the ECS service to be stable
Write-Host "Waiting for ECS service to be stable (up to 5 minutes)..."
try {
    aws ecs wait services-stable `
        --cluster ${APP_NAME}-cluster `
        --services ${APP_NAME}-service `
        --region $AWS_REGION
    Write-Host "ECS service is stable"
} 
catch {
    Write-Host "Warning: Timed out waiting for ECS service to stabilize. Continuing anyway..."
    # Wait a bit more to give service time to initialize
    Start-Sleep -Seconds 60
    Write-Host "Will attempt to proceed with available tasks..."
}

# Get the task ARN - list all tasks, not just running ones
Write-Host "Checking for tasks..."
$TASK_ARNS = (aws ecs list-tasks `
        --cluster ${APP_NAME}-cluster `
        --service-name ${APP_NAME}-service `
        --query 'taskArns' `
        --output json `
        --region $AWS_REGION)

if ($TASK_ARNS -eq "[]" -or -not $TASK_ARNS) {
    Write-Host "No tasks found. Waiting for tasks to start..."
    # Wait for tasks to start (up to 3 minutes)
    for ($i = 0; $i -lt 18; $i++) {
        Start-Sleep -Seconds 10
        $TASK_ARNS = (aws ecs list-tasks `
                --cluster ${APP_NAME}-cluster `
                --service-name ${APP_NAME}-service `
                --query 'taskArns' `
                --output json `
                --region $AWS_REGION)
        
        if ($TASK_ARNS -ne "[]" -and $TASK_ARNS) {
            Write-Host "Tasks found!"
            break
        }
        Write-Host "Waiting for tasks to start ($($i+1)/18)..."
    }
    
    if ($TASK_ARNS -eq "[]" -or -not $TASK_ARNS) {
        Write-Host "No tasks found even after waiting. Deployment might have failed."
        Write-Host "Please check the ECS console for more details."
        
        # Provide app URL anyway
        $APP_URL = "https://${SUBDOMAIN}.${DOMAIN_NAME}"
        Write-Host "Your application should be available at: $APP_URL once deployment completes"
        Write-Host "Please wait 5-10 minutes for the service to initialize and DNS to propagate."
        exit 1
    }
}

# Extract the first task ARN
$TASK_ARN = $TASK_ARNS | ConvertFrom-Json | Select-Object -First 1

Write-Host "Found task ARN: $TASK_ARN"

# Check task details
try {
    $TASK_DETAILS = (aws ecs describe-tasks `
            --cluster ${APP_NAME}-cluster `
            --tasks $TASK_ARN `
            --region $AWS_REGION)
    
    # Get health status
    $HEALTH_STATUS = ($TASK_DETAILS | ConvertFrom-Json).tasks[0].healthStatus
    Write-Host "Task health status: $HEALTH_STATUS"
    
    # Get last status
    $LAST_STATUS = ($TASK_DETAILS | ConvertFrom-Json).tasks[0].lastStatus
    Write-Host "Task last status: $LAST_STATUS"
    
    # Even if task is unhealthy but running, try to get its IP
    if ($LAST_STATUS -eq "RUNNING" -or $LAST_STATUS -eq "PROVISIONING") {
        $TASK_IP = ($TASK_DETAILS | ConvertFrom-Json).tasks[0].attachments[0].details | 
            Where-Object { $_.name -eq "privateIPv4Address" } | 
            Select-Object -ExpandProperty value
    }
    else {
        Write-Host "Task is not running (status: $LAST_STATUS). Will wait longer..."
        Start-Sleep -Seconds 30
        
        # Try again
        $TASK_DETAILS = (aws ecs describe-tasks `
                --cluster ${APP_NAME}-cluster `
                --tasks $TASK_ARN `
                --region $AWS_REGION)
        
        $TASK_IP = ($TASK_DETAILS | ConvertFrom-Json).tasks[0].attachments[0].details | 
            Where-Object { $_.name -eq "privateIPv4Address" } | 
            Select-Object -ExpandProperty value
    }
}
catch {
    Write-Host "Error getting task details: $_"
    Write-Host "Trying alternative approach to get task IP..."
    
    # Wait a bit for task to initialize networking
    Start-Sleep -Seconds 30
    
    # Try again with a different approach
    try {
        $TASK_DETAILS = (aws ecs describe-tasks `
                --cluster ${APP_NAME}-cluster `
                --tasks $TASK_ARN `
                --region $AWS_REGION)
        
        $TASK_IP = ($TASK_DETAILS | ConvertFrom-Json).tasks[0].attachments[0].details | 
            Where-Object { $_.name -eq "privateIPv4Address" } | 
            Select-Object -ExpandProperty value
    }
    catch {
        Write-Host "Still couldn't get task details. Providing general instructions..."
        
        # Provide app URL even though we couldn't register the target
        $APP_URL = "https://${SUBDOMAIN}.${DOMAIN_NAME}"
        Write-Host "Your application should be available at: $APP_URL once deployment completes"
        Write-Host "Please wait 5-10 minutes for the service to initialize and DNS to propagate."
        
        Write-Host "To check status manually, visit the AWS Console:"
        Write-Host "1. Go to ECS → Clusters → ${APP_NAME}-cluster → Services → ${APP_NAME}-service"
        Write-Host "2. Check 'Tasks' tab to see running tasks"
        Write-Host "3. Visit CloudWatch logs at /ecs/${APP_NAME} to see container logs"
        exit 1
    }
}

if (-not $TASK_IP) {
    Write-Host "No IP address found for the task even after waiting"
    Write-Host "Please check task status in AWS console. The service may still be initializing."
    
    # Provide app URL even though we couldn't register the target
    $APP_URL = "https://${SUBDOMAIN}.${DOMAIN_NAME}"
    Write-Host "Your application should be available at: $APP_URL once deployment completes"
    Write-Host "Please wait 5-10 minutes for the service to initialize and DNS to propagate."
    exit 1
}

Write-Host "Found task IP: $TASK_IP"

# Register the task IP with the target group
try {
    aws elbv2 register-targets `
        --target-group-arn $TARGET_GROUP_ARN `
        --targets "Id=$TASK_IP,Port=$ECS_CONTAINER_PORT" `
        --region $AWS_REGION

    Write-Host "Registered task with target group"
}
catch {
    Write-Host "Warning: Could not register target with target group: $_"
    Write-Host "The service may still start correctly as ECS will register it automatically."
}

# Wait for the target to be healthy
Write-Host "Waiting for target to be healthy (this may take up to 5 minutes)..."
try {
    aws elbv2 wait target-in-service `
        --target-group-arn $TARGET_GROUP_ARN `
        --targets "Id=$TASK_IP,Port=$ECS_CONTAINER_PORT" `
        --region $AWS_REGION

    Write-Host "Target is healthy"
}
catch {
    Write-Host "Warning: Target health check timed out"
    Write-Host "The application may still become available shortly"
}

# Get the application URL
$APP_URL = "https://${SUBDOMAIN}.${DOMAIN_NAME}"

Write-Host "Deployment completed!"
Write-Host "Your application should be available at: $APP_URL"
Write-Host "Please wait a few minutes for DNS propagation to complete."
Write-Host "You can check the application status by visiting: $APP_URL/api/health" 
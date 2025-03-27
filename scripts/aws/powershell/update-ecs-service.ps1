# Get the script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Updating ECS Service with new task definition..."

# Register the new task definition
Write-Host "Registering new task definition..."
$TASK_DEFINITION_ARN = (aws ecs register-task-definition `
        --cli-input-json "file://$ScriptDir/task-definition.json" `
        --region eu-west-1 `
        --query 'taskDefinition.taskDefinitionArn' `
        --output text)

if (-not $TASK_DEFINITION_ARN -or $TASK_DEFINITION_ARN -eq "None") {
    Write-Host "Failed to register task definition"
    exit 1
}

Write-Host "Task definition registered: $TASK_DEFINITION_ARN"

# Update the ECS service with new task definition
Write-Host "Updating ECS service with new task definition..."
aws ecs update-service `
    --cluster feature-poll-cluster `
    --service feature-poll-service `
    --task-definition $TASK_DEFINITION_ARN `
    --force-new-deployment `
    --health-check-grace-period-seconds 300 `
    --region eu-west-1

Write-Host "ECS service updated. New tasks will use the updated task definition with proper environment variables."
Write-Host "It may take a few minutes for the new tasks to start and become healthy."

Write-Host "You can now run the following command to monitor the deployment:"
Write-Host "aws ecs describe-services --cluster feature-poll-cluster --services feature-poll-service --region eu-west-1"

Write-Host "Once the service is stable, you can run the 09-finalize-deployment.ps1 script to complete the deployment." 
# Get the directory where the script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Source all the configuration files
. "$ScriptDir\01-setup-variables.ps1"
. "$ScriptDir\vpc-config.ps1"
. "$ScriptDir\rds-config.ps1"
. "$ScriptDir\ecr-config.ps1"
. "$ScriptDir\secrets-config.ps1"

# Source certificate config if it exists
if (Test-Path "$ScriptDir\certificate-config.ps1") {
  . "$ScriptDir\certificate-config.ps1"
}
else {
  Write-Host "No certificate configuration found. Will create HTTP-only listeners."
}

# Remove any existing role with the same name
try {
  Write-Host "Cleaning up any existing roles..."
  aws iam delete-role --role-name ${APP_NAME}-ecs-execution-role --region $AWS_REGION
  Write-Host "Removed existing role."
  # Wait for role deletion to propagate
  Start-Sleep -Seconds 10
}
catch {
  Write-Host "No existing role found, continuing with setup."
}

Write-Host "Creating ECS resources..."

# Create ECS service-linked role if it doesn't exist
try {
  aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com --region $AWS_REGION
  Write-Host "Created ECS service-linked role"
}
catch {
  Write-Host "ECS service-linked role already exists or could not be created: $_"
}

# Create ECS cluster
Write-Host "Creating ECS cluster..."
$jsonCapacityStrategy = ConvertTo-Json -Depth 5 -Compress @(
  @{
    capacityProvider = "FARGATE_SPOT"
    weight           = 1
  },
  @{
    capacityProvider = "FARGATE"
    weight           = 0
  }
)

# Convert JSON to a file to avoid escaping issues
$jsonCapacityStrategy | Out-File -FilePath "$ScriptDir\capacity-strategy.json" -Encoding ASCII -NoNewline

aws ecs create-cluster `
  --cluster-name ${APP_NAME}-cluster `
  --capacity-providers FARGATE FARGATE_SPOT `
  --default-capacity-provider-strategy file://"$ScriptDir\capacity-strategy.json" `
  --region $AWS_REGION

Write-Host "Created ECS cluster: ${APP_NAME}-cluster"

# Get existing ALB security group
$ALB_SG_ID = (aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=${APP_NAME}-alb-sg" "Name=vpc-id,Values=$VPC_ID" `
    --query 'SecurityGroups[0].GroupId' `
    --output text `
    --region $AWS_REGION)

if (-not $ALB_SG_ID -or $ALB_SG_ID -eq "None") {
  # Create ALB security group if it doesn't exist
  Write-Host "Creating ALB security group..."
  $ALB_SG_ID = (aws ec2 create-security-group `
      --group-name ${APP_NAME}-alb-sg `
      --description "Security group for ${APP_NAME} ALB" `
      --vpc-id $VPC_ID `
      --query 'GroupId' `
      --output text `
      --region $AWS_REGION)
  Write-Host "Created ALB security group: $ALB_SG_ID"
}
else {
  Write-Host "Using existing ALB security group: $ALB_SG_ID"
}

# Allow HTTP and HTTPS traffic from anywhere (ignore errors if rules already exist)
try {
  aws ec2 authorize-security-group-ingress `
    --group-id $ALB_SG_ID `
    --protocol tcp `
    --port 80 `
    --cidr 0.0.0.0/0 `
    --region $AWS_REGION
  Write-Host "Added HTTP ingress rule to ALB security group"
}
catch {
  Write-Host "HTTP ingress rule already exists in ALB security group"
}

try {
  aws ec2 authorize-security-group-ingress `
    --group-id $ALB_SG_ID `
    --protocol tcp `
    --port 443 `
    --cidr 0.0.0.0/0 `
    --region $AWS_REGION
  Write-Host "Added HTTPS ingress rule to ALB security group"
}
catch {
  Write-Host "HTTPS ingress rule already exists in ALB security group"
}

Write-Host "Configured ALB security group ingress rules"

# Get existing ECS task security group
$ECS_SG_ID = (aws ec2 describe-security-groups `
    --filters "Name=group-name,Values=${APP_NAME}-ecs-sg" "Name=vpc-id,Values=$VPC_ID" `
    --query 'SecurityGroups[0].GroupId' `
    --output text `
    --region $AWS_REGION)

if (-not $ECS_SG_ID -or $ECS_SG_ID -eq "None") {
  # Create ECS task security group if it doesn't exist
  Write-Host "Creating ECS security group..."
  $ECS_SG_ID = (aws ec2 create-security-group `
      --group-name ${APP_NAME}-ecs-sg `
      --description "Security group for ${APP_NAME} ECS tasks" `
      --vpc-id $VPC_ID `
      --query 'GroupId' `
      --output text `
      --region $AWS_REGION)
  Write-Host "Created ECS task security group: $ECS_SG_ID"
}
else {
  Write-Host "Using existing ECS task security group: $ECS_SG_ID"
}

# Allow traffic from the ALB security group
try {
  aws ec2 authorize-security-group-ingress `
    --group-id $ECS_SG_ID `
    --protocol tcp `
    --port $ECS_CONTAINER_PORT `
    --source-group $ALB_SG_ID `
    --region $AWS_REGION
  Write-Host "Added ingress rule to ECS task security group"
}
catch {
  Write-Host "Ingress rule already exists in ECS task security group"
}

Write-Host "Configured ECS task security group ingress rules"

# Get existing ALB
$ALB_ARN = (aws elbv2 describe-load-balancers `
    --names ${APP_NAME}-alb `
    --query 'LoadBalancers[0].LoadBalancerArn' `
    --output text `
    --region $AWS_REGION 2>$null)

if (-not $ALB_ARN -or $ALB_ARN -eq "None") {
  # Create ALB if it doesn't exist
  Write-Host "Creating application load balancer..."
  $ALB_ARN = (aws elbv2 create-load-balancer `
      --name ${APP_NAME}-alb `
      --subnets $PUBLIC_SUBNET_1_ID $PUBLIC_SUBNET_2_ID `
      --security-groups $ALB_SG_ID `
      --scheme internet-facing `
      --type application `
      --query 'LoadBalancers[0].LoadBalancerArn' `
      --output text `
      --region $AWS_REGION)
  Write-Host "Created application load balancer: $ALB_ARN"
  
  # Give AWS time to fully provision the ALB
  Write-Host "Waiting for ALB to be fully provisioned..."
  Start-Sleep -Seconds 30
}
else {
  Write-Host "Using existing application load balancer: $ALB_ARN"
}

# Get existing target group
$TARGET_GROUP_ARN = (aws elbv2 describe-target-groups `
    --names ${APP_NAME}-tg `
    --query 'TargetGroups[0].TargetGroupArn' `
    --output text `
    --region $AWS_REGION 2>$null)

if (-not $TARGET_GROUP_ARN -or $TARGET_GROUP_ARN -eq "None") {
  # Create target group if it doesn't exist
  Write-Host "Creating target group..."
  $TARGET_GROUP_ARN = (aws elbv2 create-target-group `
      --name ${APP_NAME}-tg `
      --protocol HTTP `
      --port $ECS_CONTAINER_PORT `
      --vpc-id $VPC_ID `
      --target-type ip `
      --health-check-path /api/health `
      --health-check-interval-seconds 30 `
      --health-check-timeout-seconds 5 `
      --healthy-threshold-count 2 `
      --unhealthy-threshold-count 2 `
      --query 'TargetGroups[0].TargetGroupArn' `
      --output text `
      --region $AWS_REGION)
  Write-Host "Created target group: $TARGET_GROUP_ARN"
}
else {
  Write-Host "Using existing target group: $TARGET_GROUP_ARN"
}

# Create HTTP listener with properly formatted JSON
try {
  # Create the default action JSON without escaping issues
  $defaultActions = @(
    @{
      Type           = "forward"
      TargetGroupArn = $TARGET_GROUP_ARN
    }
  )
  $defaultActionsJson = ConvertTo-Json -Depth 5 -Compress $defaultActions
  $defaultActionsJson | Out-File -FilePath "$ScriptDir\default-actions.json" -Encoding ASCII -NoNewline
  
  Write-Host "Creating HTTP listener..."
  $HTTP_LISTENER_ARN = (aws elbv2 create-listener `
      --load-balancer-arn $ALB_ARN `
      --protocol HTTP `
      --port 80 `
      --default-actions file://"$ScriptDir\default-actions.json" `
      --query 'Listeners[0].ListenerArn' `
      --output text `
      --region $AWS_REGION)
      
  if ($HTTP_LISTENER_ARN -and $HTTP_LISTENER_ARN -ne "None") {
    Write-Host "Created HTTP listener: $HTTP_LISTENER_ARN"
  }
  else {
    Write-Host "Created HTTP listener but couldn't get ARN"
  }
}
catch {
  Write-Host "HTTP listener already exists or could not be created: $_"
}

# Create IAM execution role for ECS tasks
$ECS_EXECUTION_ROLE_NAME = "${APP_NAME}-ecs-execution-role"

# Create IAM policy document for assume role
$assumeRolePolicy = @'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
'@

# Write policy to file with proper encoding
$assumeRolePolicy | Out-File -FilePath "$ScriptDir\assume-role-policy.json" -Encoding ASCII -NoNewline
Write-Host "Created assume role policy file"

# Wait for file to be written
Start-Sleep -Seconds 2

# Create IAM execution role
try {
  Write-Host "Creating IAM execution role..."
  aws iam create-role `
    --role-name $ECS_EXECUTION_ROLE_NAME `
    --assume-role-policy-document file://"$ScriptDir\assume-role-policy.json" `
    --region $AWS_REGION

  Write-Host "Created IAM execution role: $ECS_EXECUTION_ROLE_NAME"

  # Wait for role to propagate
  Write-Host "Waiting for role to propagate..."
  Start-Sleep -Seconds 20
}
catch {
  Write-Host "Error creating IAM role: $_"
  Start-Sleep -Seconds 5
}

# Attach policies to the role
try {
  Write-Host "Attaching AmazonECSTaskExecutionRolePolicy to role..."
  aws iam attach-role-policy `
    --role-name $ECS_EXECUTION_ROLE_NAME `
    --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" `
    --region $AWS_REGION
  
  Write-Host "Attached AmazonECSTaskExecutionRolePolicy to role"
  # Give AWS time to process the policy attachment
  Start-Sleep -Seconds 10
}
catch {
  Write-Host "Failed to attach ECS execution policy: $_"
}

# Create policy for Secrets Manager access with properly formatted ARN
$secretsPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "$SECRET_ARN"
      ]
    }
  ]
}
"@

# Write secrets policy to file with proper encoding
$secretsPolicy | Out-File -FilePath "$ScriptDir\secrets-policy.json" -Encoding ASCII -NoNewline
Write-Host "Created secrets policy file"

# Wait for file to be written
Start-Sleep -Seconds 2

# Create and attach the secrets policy
try {
  Write-Host "Creating secrets policy..."
  $SECRETS_POLICY_ARN = (aws iam create-policy `
      --policy-name "${APP_NAME}-secrets-policy" `
      --policy-document file://"$ScriptDir\secrets-policy.json" `
      --query 'Policy.Arn' `
      --output text `
      --region $AWS_REGION)

  if ($SECRETS_POLICY_ARN -and $SECRETS_POLICY_ARN -ne "None") {
    Write-Host "Created secrets policy: $SECRETS_POLICY_ARN"
    
    Write-Host "Attaching secrets policy to role..."
    aws iam attach-role-policy `
      --role-name $ECS_EXECUTION_ROLE_NAME `
      --policy-arn $SECRETS_POLICY_ARN `
      --region $AWS_REGION
    Write-Host "Attached secrets policy to IAM role"
    # Give AWS time to process the policy attachment
    Start-Sleep -Seconds 10
  }
  else {
    Write-Host "Failed to create secrets policy, cannot attach"
  }
}
catch {
  Write-Host "Failed to create or attach secrets policy: $_"
}

# Get the execution role ARN
try {
  Write-Host "Getting execution role ARN..."
  $ECS_EXECUTION_ROLE_ARN = (aws iam get-role `
      --role-name $ECS_EXECUTION_ROLE_NAME `
      --query 'Role.Arn' `
      --output text `
      --region $AWS_REGION)
  
  if ($ECS_EXECUTION_ROLE_ARN -and $ECS_EXECUTION_ROLE_ARN -ne "None") {
    Write-Host "ECS execution role ARN: $ECS_EXECUTION_ROLE_ARN"
  }
  else {
    throw "Unable to get role ARN"
  }
}
catch {
  Write-Host "Failed to get execution role ARN: $_"
  $ECS_EXECUTION_ROLE_ARN = "arn:aws:iam::$AWS_ACCOUNT_ID:role/$ECS_EXECUTION_ROLE_NAME"
  Write-Host "Using constructed role ARN: $ECS_EXECUTION_ROLE_ARN"
}

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
  executionRoleArn        = $ECS_EXECUTION_ROLE_ARN
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

# Create load balancer configuration for ECS service
$loadBalancers = @(
  @{
    targetGroupArn = $TARGET_GROUP_ARN
    containerName  = $APP_NAME
    containerPort  = [int]$ECS_CONTAINER_PORT
  }
)

$loadBalancersJson = ConvertTo-Json -Depth 5 -Compress $loadBalancers
$loadBalancersJson | Out-File -FilePath "$ScriptDir\load-balancers.json" -Encoding ASCII -NoNewline

# Create network configuration for ECS service
$networkConfig = @{
  awsvpcConfiguration = @{
    subnets        = @($PUBLIC_SUBNET_1_ID, $PUBLIC_SUBNET_2_ID)
    securityGroups = @($ECS_SG_ID)
    assignPublicIp = "ENABLED"
  }
}

$networkConfigJson = ConvertTo-Json -Depth 5 -Compress $networkConfig
$networkConfigJson | Out-File -FilePath "$ScriptDir\network-config.json" -Encoding ASCII -NoNewline

# Create ECS service
try {
  Write-Host "Creating ECS service..."
  $result = aws ecs create-service `
    --cluster ${APP_NAME}-cluster `
    --service-name ${APP_NAME}-service `
    --task-definition $TASK_DEFINITION_ARN `
    --desired-count $ECS_SERVICE_COUNT `
    --launch-type FARGATE `
    --platform-version LATEST `
    --network-configuration file://"$ScriptDir\network-config.json" `
    --load-balancers file://"$ScriptDir\load-balancers.json" `
    --health-check-grace-period-seconds 120 `
    --scheduling-strategy REPLICA `
    --deployment-configuration "maximumPercent=200,minimumHealthyPercent=100" `
    --deployment-controller "type=ECS" `
    --region $AWS_REGION

  Write-Host "Created ECS service: ${APP_NAME}-service"
}
catch {
  Write-Host "Failed to create ECS service: $_"
  
  # Try a different approach without the load balancer if there was an error
  try {
    Write-Host "Retrying service creation without load balancer..."
    $result = aws ecs create-service `
      --cluster ${APP_NAME}-cluster `
      --service-name ${APP_NAME}-service-basic `
      --task-definition $TASK_DEFINITION_ARN `
      --desired-count $ECS_SERVICE_COUNT `
      --launch-type FARGATE `
      --platform-version LATEST `
      --network-configuration file://"$ScriptDir\network-config.json" `
      --scheduling-strategy REPLICA `
      --deployment-configuration "maximumPercent=200,minimumHealthyPercent=100" `
      --deployment-controller "type=ECS" `
      --region $AWS_REGION
    
    Write-Host "Created basic ECS service without load balancer."
  }
  catch {
    Write-Host "Failed to create basic ECS service: $_"
  }
}

# Get the load balancer DNS name
try {
  $ALB_DNS_NAME = (aws elbv2 describe-load-balancers `
      --load-balancer-arns $ALB_ARN `
      --query 'LoadBalancers[0].DNSName' `
      --output text `
      --region $AWS_REGION)
  
  Write-Host "Application load balancer DNS name: $ALB_DNS_NAME"
}
catch {
  Write-Host "Could not get load balancer DNS name: $_"
  $ALB_DNS_NAME = "unknown"
}

# Save ALB configuration to a file
$ALBConfig = @"
# ALB Configuration
`$ALB_ARN = "$ALB_ARN"
`$ALB_DNS_NAME = "$ALB_DNS_NAME"
`$TARGET_GROUP_ARN = "$TARGET_GROUP_ARN"
`$ALB_SG_ID = "$ALB_SG_ID"
`$ECS_SG_ID = "$ECS_SG_ID"
"@

$ALBConfig | Out-File -FilePath "$ScriptDir\alb-config.ps1" -Encoding UTF8

Write-Host "ALB configuration saved to $ScriptDir\alb-config.ps1"
Write-Host "ECS resources creation completed"

# Clean up temporary files
Remove-Item -Path "$ScriptDir\assume-role-policy.json" -ErrorAction SilentlyContinue
Remove-Item -Path "$ScriptDir\secrets-policy.json" -ErrorAction SilentlyContinue
Remove-Item -Path "$ScriptDir\task-definition.json" -ErrorAction SilentlyContinue
Remove-Item -Path "$ScriptDir\load-balancers.json" -ErrorAction SilentlyContinue
Remove-Item -Path "$ScriptDir\network-config.json" -ErrorAction SilentlyContinue
Remove-Item -Path "$ScriptDir\default-actions.json" -ErrorAction SilentlyContinue
Remove-Item -Path "$ScriptDir\capacity-strategy.json" -ErrorAction SilentlyContinue
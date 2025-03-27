# ... (Load environment variables, Invoke-AWSCommand function) ...
. "$PSScriptRoot\vpc-config.ps1"
. "$PSScriptRoot\rds-config.ps1"
. "$PSScriptRoot\ecr-config.ps1"
. "$PSScriptRoot\certificate-config.ps1"
. "$PSScriptRoot\secrets-config.ps1" # Contains SECRET_PARAMETER_NAME_PREFIX

Write-Host "Starting ECS resources creation script..."
$AWS_ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text --region $env:AWS_REGION)

# --- Create/Get Execution Role ---
# ... (Existing role creation/check logic) ...

# --- Create/Get SSM Parameter Access Policy ---
$SsmPolicyName = "$($env:APP_NAME)-ssm-parameter-access-policy"
Write-Host "Checking/Creating IAM Policy: $SsmPolicyName..."
$SsmPolicyArn = (aws iam list-policies --scope Local --query "Policies[?PolicyName=='$SsmPolicyName'].Arn" --output text --region $env:AWS_REGION)

if ([string]::IsNullOrWhiteSpace($SsmPolicyArn)) {
    Write-Host "Creating SSM Parameter Access Policy..."
    # --- Update Resource ARN for hyphenated pattern ---
    $SsmPolicyDoc = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameters"
      ],
      "Resource": [
        "arn:aws:ssm:$($env:AWS_REGION):$AWS_ACCOUNT_ID:parameter/$($env:SECRET_PARAMETER_NAME_PREFIX)-*"
      ]
    }
  ]
}
"@
    $policyResult = aws iam create-policy --policy-name $SsmPolicyName --policy-document $SsmPolicyDoc --description "Allows ECS tasks to read parameters starting with $($env:SECRET_PARAMETER_NAME_PREFIX)-" --query 'Policy.Arn' --output text --region $env:AWS_REGION
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create SSM policy"; exit 1 }
    $SsmPolicyArn = $policyResult
    Write-Host "Created SSM Policy ARN: $SsmPolicyArn"
} else {
    Write-Host "Found existing SSM Policy ARN: $SsmPolicyArn"
}

# Attach SSM policy to Execution Role
Write-Host "Attaching SSM policy $SsmPolicyArn to role $EcsExecutionRoleName..."
$attachSsmCommand = "aws iam attach-role-policy --role-name $EcsExecutionRoleName --policy-arn $SsmPolicyArn --region $env:AWS_REGION"
Invoke-AWSCommand -Command $attachSsmCommand -IgnoreErrors # Ignore if already attached

# Attach standard ECS Task Execution Role Policy
Write-Host "Attaching standard ECS policy to role $EcsExecutionRoleName..."
$stdEcsPolicyArn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
$attachStdCommand = "aws iam attach-role-policy --role-name $EcsExecutionRoleName --policy-arn $stdEcsPolicyArn --region $env:AWS_REGION"
Invoke-AWSCommand -Command $attachStdCommand -IgnoreErrors # Ignore if already attached

# --- Create/Get Security Groups ---
# ... (Existing SG creation/check logic) ...
# Ensure DB Ingress rule is added correctly (already seems correct)
Write-Host "Authorizing access from ECS SG ($EcsSgId) to DB SG ($($env:SECURITY_GROUP_ID)) on port $($env:DB_PORT)..."
$dbIngressCommand = "aws ec2 authorize-security-group-ingress --group-id $($env:SECURITY_GROUP_ID) --protocol tcp --port $($env:DB_PORT) --source-group $EcsSgId --region $env:AWS_REGION"
Invoke-AWSCommand -Command $dbIngressCommand -IgnoreErrors # Ignore if rule exists

# --- Create/Get ALB, Target Group, Listeners ---
# ... (Existing ALB/TG/Listener creation/check logic) ...

# --- Get ALB Canonical Hosted Zone ID ---
Write-Host "Retrieving ALB Canonical Hosted Zone ID..."
$albDetailsCommand = "aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text --region $env:AWS_REGION"
$ALB_HOSTED_ZONE_ID = Invoke-AWSCommand -Command $albDetailsCommand
if ([string]::IsNullOrWhiteSpace($ALB_HOSTED_ZONE_ID)) { Write-Error "Failed to retrieve ALB Canonical Hosted Zone ID"; exit 1 }
Write-Host "ALB Canonical Hosted Zone ID: $ALB_HOSTED_ZONE_ID"

# --- Prepare Task Definition ---
Write-Host "Preparing Task Definition..."
# ===>>> IMPORTANT: Add substitution logic here <<<===
Write-Host "!!! Placeholder: Task definition requires variable substitution logic before registration !!!"
# Example: Read template, replace placeholders, write to task-definition.json
# $taskDefTemplate = Get-Content -Path "$PSScriptRoot\task-definition.json.template" -Raw
# $taskDefContent = $taskDefTemplate `
#    -replace '%%ECS_EXECUTION_ROLE_ARN%%', $EcsExecutionRoleArn `
#    -replace '%%REPOSITORY_URI%%', $env:REPOSITORY_URI `
#    -replace '%%SECRET_PARAMETER_NAME_PREFIX%%', $env:SECRET_PARAMETER_NAME_PREFIX `
#    # ... other replacements
# $taskDefContent | Out-File -FilePath "$PSScriptRoot\task-definition.json" -Encoding utf8

# --- Update Task Definition JSON content (using hyphenated secrets) ---
$taskDefinitionJson = @"
{
  "family": "$($env:APP_NAME)-task",
  "networkMode": "awsvpc",
  "executionRoleArn": "$EcsExecutionRoleArn",
  "taskRoleArn": "$EcsExecutionRoleArn",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "$($env:ECS_TASK_CPU)",
  "memory": "$($env:ECS_TASK_MEMORY)",
  "containerDefinitions": [
    {
      "name": "$($env:ECS_CONTAINER_NAME)",
      "image": "$($env:REPOSITORY_URI):latest",
      "essential": true,
      "portMappings": [ { "containerPort": $($env:ECS_CONTAINER_PORT), "protocol": "tcp" } ],
      "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
             "awslogs-group": "/ecs/$($env:APP_NAME)",
             "awslogs-region": "$($env:AWS_REGION)",
             "awslogs-stream-prefix": "ecs",
             "awslogs-create-group": "true"
           }
      },
      "secrets": [
         {"name": "DATABASE_URL", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-DATABASE_URL"},
         {"name": "DIRECT_URL", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-DIRECT_URL"},
         {"name": "NEXT_PUBLIC_APP_URL", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-NEXT_PUBLIC_APP_URL"},
         {"name": "NEXTAUTH_URL", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-NEXTAUTH_URL"},
         {"name": "NEXTAUTH_SECRET", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-NEXTAUTH_SECRET"},
         {"name": "EMAIL_SERVER_HOST", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-EMAIL_SERVER_HOST"},
         {"name": "EMAIL_SERVER_PORT", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-EMAIL_SERVER_PORT"},
         {"name": "EMAIL_SERVER_USER", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-EMAIL_SERVER_USER"},
         {"name": "EMAIL_SERVER_PASSWORD", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-EMAIL_SERVER_PASSWORD"},
         {"name": "EMAIL_FROM", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-EMAIL_FROM"},
         {"name": "GOOGLE_CLIENT_ID", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-GOOGLE_CLIENT_ID"},
         {"name": "GOOGLE_CLIENT_SECRET", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-GOOGLE_CLIENT_SECRET"},
         {"name": "GITHUB_ID", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-GITHUB_ID"},
         {"name": "GITHUB_SECRET", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-GITHUB_SECRET"},
         {"name": "NODE_ENV", "valueFrom": "$($env:SECRET_PARAMETER_NAME_PREFIX)-NODE_ENV"}
       ],
      "healthCheck": {
          "command": [ "CMD-SHELL", "wget -q -O - http://localhost:$($env:ECS_CONTAINER_PORT)/api/health || exit 1" ],
          "interval": 30, "timeout": 5, "retries": 3, "startPeriod": 60
       }
    }
  ]
}
"@
$taskDefinitionFile = Join-Path -Path $PSScriptRoot -ChildPath "task-definition.json"
$taskDefinitionJson | Out-File -FilePath $taskDefinitionFile -Encoding utf8

# --- Register Task Definition ---
# ... (Existing registration logic) ...

# --- Create/Update ECS Service ---
Write-Host "Checking/Creating ECS Service: $EcsServiceName..."
# ... (Check if service exists) ...
if (-not $serviceExists) {
    Write-Host "Creating ECS Service..."
    $networkConfig = "`"awsvpcConfiguration={subnets=[`"$($env:PRIVATE_SUBNET_1_ID)`",`"$($env:PRIVATE_SUBNET_2_ID)`"],securityGroups=[`"$EcsSgId`"],assignPublicIp=DISABLED}`"" # <-- Use Private Subnets, Disabled Public IP
    $loadBalancerConfig = "[{`"targetGroupArn`":`"$TargetGroupArn`",`"containerName`":`"$($env:ECS_CONTAINER_NAME)`",`"containerPort`":$($env:ECS_CONTAINER_PORT)}]"
    $createServiceCommand = "aws ecs create-service --cluster $EcsClusterName --service-name $EcsServiceName --task-definition $TaskDefinitionArn --desired-count $($env:ECS_SERVICE_COUNT) --launch-type FARGATE --platform-version LATEST --network-configuration $networkConfig --load-balancers $loadBalancerConfig --health-check-grace-period-seconds 120 --scheduling-strategy REPLICA --deployment-configuration `"maximumPercent=200,minimumHealthyPercent=100`" --deployment-controller `"type=ECS`" --region $env:AWS_REGION --tags key=AppName,value=$($env:APP_NAME)"
    Invoke-AWSCommand -Command $createServiceCommand
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create ECS Service"; exit 1 }
    Write-Host "Created ECS service: $EcsServiceName"
} else {
    Write-Host "ECS Service $EcsServiceName already exists. Consider updating if needed."
    # Optionally add update-service logic here if required
}

# --- Save ALB Config ---
$AlbConfigFilePath = Join-Path -Path $PSScriptRoot -ChildPath "alb-config.ps1"
@"
# ALB Configuration
`$ALB_ARN = "$ALB_ARN"
`$ALB_DNS_NAME = "$ALB_DNS_NAME"
`$TARGET_GROUP_ARN = "$TargetGroupArn"
`$ALB_HOSTED_ZONE_ID = "$ALB_HOSTED_ZONE_ID" # <-- Save ALB Zone ID
`$ALB_SG_ID = "$AlbSgId"
`$ECS_SG_ID = "$EcsSgId"

# Export variables
`$env:ALB_ARN = `$ALB_ARN
`$env:ALB_DNS_NAME = `$ALB_DNS_NAME
`$env:TARGET_GROUP_ARN = `$TARGET_GROUP_ARN
`$env:ALB_HOSTED_ZONE_ID = `$ALB_HOSTED_ZONE_ID # <-- Export ALB Zone ID
`$env:ALB_SG_ID = `$ALB_SG_ID
`$env:ECS_SG_ID = `$ECS_SG_ID
"@ | Out-File -FilePath $AlbConfigFilePath -Encoding utf8
Write-Host "ALB configuration saved to $AlbConfigFilePath"

Write-Host "ECS resources setup script completed." 
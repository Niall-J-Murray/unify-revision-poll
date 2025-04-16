# --- ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = "${var.subdomain_name}-cluster"

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-cluster"
  })
}

# --- IAM Role for ECS Task Execution ---
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.subdomain_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow task execution role to fetch secrets from Secrets Manager
resource "aws_iam_policy" "secrets_manager_access" {
  name        = "${var.subdomain_name}-secrets-manager-access-policy"
  description = "Allow ECS tasks to read secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt" # Required if the secret is encrypted with a KMS key
        ],
        Effect   = "Allow",
        Resource = aws_secretsmanager_secret.app_secrets.arn
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "secrets_manager_access_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.secrets_manager_access.arn
}

# --- CloudWatch Log Group ---
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/ecs/${var.subdomain_name}-app"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# --- ECS Task Definition ---
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.subdomain_name}-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "256" # Minimal CPU units for t3.micro
  memory                   = "256" # Minimal Memory (MiB) for t3.micro
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn # Can use the same role if no other AWS services are accessed by the app itself

  container_definitions = jsonencode([
    {
      name      = "${var.subdomain_name}-app-container"
      image     = "${aws_ecr_repository.app.repository_url}:latest" # Assumes image tagged as 'latest'
      cpu       = 256
      memory    = 256
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port # Can map to the same port in awsvpc mode
          protocol      = "tcp"
        }
      ]
      # Inject secrets from Secrets Manager using the looked-up ARN
      secrets = [
        for k, v in local.app_secrets : {
          name      = k
          valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:${k}::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      # Define health check based on Dockerfile/docker-compose
      healthCheck = {
        command = [
          "CMD-SHELL",
          "wget -qO- http://localhost:${var.container_port}${var.health_check_path} || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60 # Allow time for container to start and migrations
      }
      # Add command based on Dockerfile CMD
      command = ["sh", "-c", "npx prisma migrate deploy && npm run start"]
    }
  ])

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-app-task-definition"
  })
}

# --- IAM Role for EC2 Instance Profile ---
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.subdomain_name}-ecs-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.subdomain_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
  tags = var.tags
}

# --- EC2 Launch Template for ECS Instances ---
# Use Amazon Linux 2 ECS-optimized AMI
data "aws_ami" "ecs_optimized_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# User data script to register the instance to the ECS cluster
data "template_file" "ecs_user_data" {
  template = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
              EOF
}

resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = "${var.subdomain_name}-ecs-"
  image_id      = data.aws_ami.ecs_optimized_ami.id
  instance_type = var.ec2_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  # Define network interfaces - needed for security groups and public IP
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_instance.id]
    # subnet_id is not specified here; ASG will handle placing it in specified subnets
  }

  user_data = base64encode(data.template_file.ecs_user_data.rendered)

  # Add tags to the Launch Template itself
  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-ecs-launch-template"
  })

  # Define tags to be applied to instances launched from this template
  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.subdomain_name}-ecs-instance" # Tag the instance itself
    })
  }
  # Optional: Tag EBS volumes if needed
  # tag_specifications {
  #   resource_type = "volume"
  #   tags = merge(var.tags, {
  #     Name = "${var.subdomain_name}-ecs-volume"
  #   })
  # }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Auto Scaling Group for ECS Instances (using Launch Template) ---
resource "aws_autoscaling_group" "ecs_asg" {
  name_prefix = "${var.subdomain_name}-ecs-asg-"
  # Reference the Launch Template
  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest" # Always use the latest version of the template
  }

  # Use both public subnets across the two AZs for instance placement
  vpc_zone_identifier       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  min_size                  = 1
  max_size                  = 1 # Keep it at 1 instance as requested
  desired_capacity          = 1
  health_check_type         = "EC2"
  health_check_grace_period = 300 # Allow time for instance and ECS agent to start

  # Required tag for ECS integration
  tag {
    key                 = "AmazonECSManaged"
    value               = true
    propagate_at_launch = true # Needs to be true here too for ASG context
  }

  # Note: Instance tagging is now handled within the Launch Template's tag_specifications

  # Prevent ASG from terminating instances during updates if ECS service needs them
  # service_linked_role_arn = aws_iam_role.ecs_service_linked_role.arn # Might need `aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com`
  # suspended_processes = ["ReplaceUnhealthy", "AZRebalance"]
}

# --- ECS Service ---
resource "aws_ecs_service" "app" {
  name            = "${var.subdomain_name}-app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "EC2"

  # Network configuration needed for awsvpc mode
  network_configuration {
    # Use public subnets for task placement and enable public IP
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.ecs_task.id]
    # assign_public_ip = true # Removed: Only valid for FARGATE launch type
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "${var.subdomain_name}-app-container"
    container_port   = var.container_port
  }

  # Ensure ASG instances are ready before starting service tasks
  depends_on = [aws_autoscaling_group.ecs_asg, aws_lb_listener.https]

  # Change deployment strategy to allow task replacement on ENI-limited instances
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100 # Optional: Can be 100 or 200, but 100 is clearer with min 0

  # Optional: Health check grace period for the service
  health_check_grace_period_seconds = 120 # Give tasks time to start and become healthy

  lifecycle {
    ignore_changes = [task_definition] # Avoid recreation if only task definition changes
  }

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-app-service"
  })
}
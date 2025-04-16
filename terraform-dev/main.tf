provider "aws" {
  region = var.aws_region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0" # Use a recent AWS provider version
    }
  }
  required_version = ">= 1.5"
}

# --- Data Sources ---
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# Get zone details
data "aws_availability_zone" "az_a" {
  name = var.availability_zone_a
}
data "aws_availability_zone" "az_b" {
  name = var.availability_zone_b
}

# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-vpc"
  })
}

# --- Subnets (Multi-AZ) ---
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24" # First public subnet CIDR
  availability_zone       = data.aws_availability_zone.az_a.name
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-public-subnet-${data.aws_availability_zone.az_a.zone_id}"
    Tier = "Public"
  })
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24" # First private subnet CIDR
  availability_zone = data.aws_availability_zone.az_a.name

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-private-subnet-${data.aws_availability_zone.az_a.zone_id}"
    Tier = "Private"
  })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24" # Second public subnet CIDR
  availability_zone       = data.aws_availability_zone.az_b.name
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-public-subnet-${data.aws_availability_zone.az_b.zone_id}"
    Tier = "Public"
  })
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24" # Second private subnet CIDR
  availability_zone = data.aws_availability_zone.az_b.name

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-private-subnet-${data.aws_availability_zone.az_b.zone_id}"
    Tier = "Private"
  })
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-igw"
  })
}

# --- Route Tables ---
# Public Route Table (routes to IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-public-rtb"
  })
}

# --- Route Table Associations ---
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id # Associate with the same public route table
}

# --- Security Groups ---

# Security Group for ALB (allows HTTP/HTTPS from anywhere)
resource "aws_security_group" "lb" {
  name        = "${var.subdomain_name}-lb-sg"
  description = "Allow HTTP/HTTPS inbound traffic to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-lb-sg"
  })
}

# Security Group for ECS EC2 Instances (allows traffic from ALB and outbound)
resource "aws_security_group" "ecs_instance" {
  name        = "${var.subdomain_name}-ecs-instance-sg"
  description = "Allow traffic from ALB and outbound access for ECS instances"
  vpc_id      = aws_vpc.main.id

  # Allow traffic from the ALB on the container port
  ingress {
    description     = "App traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id] # Allow traffic only from the ALB
  }

  # Allow all outbound traffic (needed for pulling images, talking to AWS services, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-ecs-instance-sg"
  })
}

# Security Group for ECS Tasks (using awsvpc mode)
resource "aws_security_group" "ecs_task" {
  name        = "${var.subdomain_name}-ecs-task-sg"
  description = "Allow traffic from ALB to ECS tasks"
  vpc_id      = aws_vpc.main.id

  # Allow traffic from the ALB on the container port
  ingress {
    description     = "App traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id] # Allow traffic only from the ALB
  }

  # Allow all other outbound traffic (e.g., to external APIs, AWS services like Secrets Manager)
  egress {
    description = "Allow all other outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-ecs-task-sg"
  })
}

# Security Group for RDS instance
resource "aws_security_group" "rds" {
  name        = "${var.subdomain_name}-rds-sg"
  description = "Allow traffic from ECS tasks to RDS instance"
  vpc_id      = aws_vpc.main.id

  # Allow inbound PostgreSQL traffic from ECS tasks
  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_task.id] # Allow from the ECS task SG
  }

  # Allow inbound PostgreSQL traffic from Bastion host
  ingress {
    description     = "PostgreSQL from Bastion host"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_host.id] # Allow from the Bastion SG
  }

  # Typically no egress rules needed unless RDS needs to initiate connections (uncommon)
  # egress {
  #   from_port   = 0
  #   to_port     = 0
  #   protocol    = "-1"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-rds-sg"
  })
}

# --- Bastion Host Components (Traditional SSH) ---

# Security Group for the Bastion Host instance
resource "aws_security_group" "bastion_host" {
  name        = "${var.subdomain_name}-bastion-host-sg"
  description = "Allow SSH inbound from admin and all outbound"
  vpc_id      = aws_vpc.main.id

  # Allow SSH inbound from your IPv6 and IPv4 addresses
  ingress {
    description      = "SSH from Admin IPs"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["37.228.206.81/32"]
    ipv6_cidr_blocks = ["2a02:8084:4461:b880:d8fa:ccb2:403:955/128"]
  }

  # Allow all outbound traffic (needed for SSH replies, updates, reaching RDS)
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-bastion-host-sg"
  })
}

# EC2 Instance for Bastion Host
resource "aws_instance" "bastion_host" {
  ami           = data.aws_ami.amazon_linux_2023.id # Reuse the AMI data source
  instance_type = "t3.micro" # Small instance type is sufficient

  subnet_id                   = aws_subnet.public_a.id # Place in a PUBLIC subnet
  associate_public_ip_address = true                   # Needs a public IP

  vpc_security_group_ids = [aws_security_group.bastion_host.id]
  key_name               = "bastion-host" # Your provided key pair name

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-bastion-host"
  })
}

# --- ECR Repository ---
resource "aws_ecr_repository" "app" {
  name                 = "${var.subdomain_name}-app-repo"
  image_tag_mutability = "MUTABLE" # Or IMMUTABLE for stricter versioning

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-app-ecr-repo"
  })
}

# --- Application Load Balancer (ALB) ---
resource "aws_lb" "main" {
  name               = "${var.subdomain_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  # Use both public subnets across the two AZs
  subnets = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  enable_deletion_protection = false # Set to true for production

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-alb"
  })
}

# --- ALB Target Group ---
resource "aws_lb_target_group" "app" {
  name        = "${var.subdomain_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Required for awsvpc network mode

  health_check {
    enabled             = true
    interval            = 30
    path                = var.health_check_path
    port                = "traffic-port" # Check on the port where traffic is sent
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200" # Expect HTTP 200 OK for healthy
  }

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-app-tg"
  })
}

# --- ALB Listeners ---
# Listener for HTTP (redirects to HTTPS)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Listener for HTTPS (forwards to the Target Group)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08" # Choose an appropriate security policy
  certificate_arn   = var.acm_certificate_arn     # Use the provided ACM certificate ARN

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# --- Route 53 DNS Record ---
data "aws_route53_zone" "selected" {
  name         = "${var.domain_name}." # Note the trailing dot
  private_zone = false
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "${var.subdomain_name}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# EC2 Instance for Bastion Host
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
} 
# --- VPC Endpoints ---

# Gateway Endpoint for S3 (Free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # Associate with the private route tables
  route_table_ids = [aws_route_table.private.id]

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-s3-gateway-endpoint"
  })
}

# Security Group for Interface Endpoints (Allow HTTPS from ECS Task SG and ECS Instance SG)
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.subdomain_name}-vpc-endpoints-sg"
  description = "Allow HTTPS from ECS Tasks to VPC Interface Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTPS from ECS Tasks and Instances"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [
      aws_security_group.ecs_task.id,     # Defined in main.tf
      aws_security_group.ecs_instance.id  # Defined in main.tf
    ]
  }

  # Allow all outbound (endpoints may need to talk to other services)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-vpc-endpoints-sg"
  })
}

# --- Interface Endpoints (Have hourly cost) ---

# ECR API Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
  security_group_ids = [
    aws_security_group.vpc_endpoints.id
  ]

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-ecr-api-endpoint"
  })
}

# ECR Docker Registry Endpoint
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
  security_group_ids = [
    aws_security_group.vpc_endpoints.id
  ]

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-ecr-dkr-endpoint"
  })
}

# CloudWatch Logs Endpoint
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
  security_group_ids = [
    aws_security_group.vpc_endpoints.id
  ]

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-logs-endpoint"
  })
}

# Secrets Manager Endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
  security_group_ids = [
    aws_security_group.vpc_endpoints.id
  ]

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-secretsmanager-endpoint"
  })
}

# Potentially ECS Agent/Telemetry Endpoints (Needed if using Fargate or certain ECS features)
# Uncomment if needed, usually helps reduce NAT gateway traffic further
# resource "aws_vpc_endpoint" "ecs_agent" {
#   vpc_id              = aws_vpc.main.id
#   service_name        = "com.amazonaws.${var.aws_region}.ecs-agent"
#   vpc_endpoint_type   = "Interface"
#   private_dns_enabled = true
#
#   subnet_ids = [
#     aws_subnet.private_a.id,
#     aws_subnet.private_b.id
#   ]
#   security_group_ids = [
#     aws_security_group.vpc_endpoints.id
#   ]
#
#   tags = merge(var.tags, {
#     Name = "${var.subdomain_name}-ecs-agent-endpoint"
#   })
# }
#
# resource "aws_vpc_endpoint" "ecs_telemetry" {
#   vpc_id              = aws_vpc.main.id
#   service_name        = "com.amazonaws.${var.aws_region}.ecs-telemetry"
#   vpc_endpoint_type   = "Interface"
#   private_dns_enabled = true
#
#   subnet_ids = [
#     aws_subnet.private_a.id,
#     aws_subnet.private_b.id
#   ]
#   security_group_ids = [
#     aws_security_group.vpc_endpoints.id
#   ]
#
#   tags = merge(var.tags, {
#     Name = "${var.subdomain_name}-ecs-telemetry-endpoint"
#   })
# } 
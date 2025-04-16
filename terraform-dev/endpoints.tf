# --- VPC Endpoints ---

# Gateway Endpoint for S3 (Free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  # Removed association with the deleted private route table
  # route_table_ids = [aws_route_table.private.id]

  tags = merge(var.tags, {
    Name = "${var.subdomain_name}-s3-gateway-endpoint"
  })
}

# Security Group for Interface Endpoints (Allow HTTPS from ECS Task SG and ECS Instance SG)
# --- Removed aws_security_group.vpc_endpoints resource ---

# --- Interface Endpoints (Have hourly cost) ---

# ECR API Endpoint
# --- Removed aws_vpc_endpoint.ecr_api resource ---

# ECR Docker Registry Endpoint
# --- Removed aws_vpc_endpoint.ecr_dkr resource ---

# CloudWatch Logs Endpoint
# --- Removed aws_vpc_endpoint.logs resource ---

# Secrets Manager Endpoint
# --- Removed aws_vpc_endpoint.secretsmanager resource ---

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
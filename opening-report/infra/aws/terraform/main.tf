###############################################################################
# main.tf — scidb-beta AWS infrastructure
#
# Deploys:
#   - S3 + CloudFront for the SPA
#   - ECS/Fargate for the runtime adapter
#   - EFS for database files
#   - SQS for background job queues
#   - ElastiCache Redis for job events / workspace state
#   - RDS PostgreSQL for users, metadata, jobs
###############################################################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "${local.prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${local.prefix}-igw" })
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = merge(local.common_tags, { Name = "${local.prefix}-public-${count.index}" })
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = merge(local.common_tags, { Name = "${local.prefix}-private-${count.index}" })
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "${local.prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# S3 bucket for SPA static assets
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "spa" {
  bucket = "${local.prefix}-spa"
  tags   = local.common_tags
}

resource "aws_s3_bucket_ownership_controls" "spa" {
  bucket = aws_s3_bucket.spa.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "spa" {
  bucket                  = aws_s3_bucket.spa.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "spa" {
  bucket = aws_s3_bucket.spa.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.spa.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.spa.arn
        }
      }
    }]
  })
}

# ---------------------------------------------------------------------------
# CloudFront distribution for the SPA
# ---------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "spa" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name = aws_s3_bucket.spa.bucket_regional_domain_name
    origin_id   = "s3-spa"
  }

  default_cache_behavior {
    target_origin_id       = "s3-spa"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  # SPA fallback for client-side routing
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# S3 bucket for database files and import artifacts
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.prefix}-artifacts"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# EFS for shared database files (mounted to ECS tasks)
# ---------------------------------------------------------------------------

resource "aws_efs_file_system" "databases" {
  creation_token = "${local.prefix}-efs"
  tags           = merge(local.common_tags, { Name = "${local.prefix}-databases" })
}

resource "aws_efs_mount_target" "databases" {
  count           = 2
  file_system_id  = aws_efs_file_system.databases.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.prefix}-alb-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow HTTP/HTTPS to ALB"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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

  tags = local.common_tags
}

resource "aws_security_group" "ecs" {
  name        = "${local.prefix}-ecs-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow traffic from ALB to ECS tasks"

  ingress {
    from_port       = 5001
    to_port         = 5001
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_security_group" "efs" {
  name        = "${local.prefix}-efs-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow NFS from ECS tasks"

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_security_group" "redis" {
  name        = "${local.prefix}-redis-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow Redis from ECS tasks"

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_security_group" "rds" {
  name        = "${local.prefix}-rds-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow PostgreSQL from ECS tasks"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "${local.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = local.common_tags
}

resource "aws_lb_target_group" "adapter" {
  name     = "${local.prefix}-adapter-tg"
  port     = 5001
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/api/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.adapter.arn
  }
}

# ---------------------------------------------------------------------------
# ECS cluster + Fargate task definition
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "${local.prefix}-cluster"
  tags = local.common_tags
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.prefix}-task-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name = "${local.prefix}-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Allow ECS tasks to access S3 artifacts bucket and EFS
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${local.prefix}-task-s3"
  role = aws_iam_role.ecs_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.artifacts.arn,
        "${aws_s3_bucket.artifacts.arn}/*"
      ]
    }]
  })
}

resource "aws_ecs_task_definition" "adapter" {
  family                   = "${local.prefix}-adapter"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "adapter"
      image     = var.adapter_image
      essential = true
      portMappings = [{
        containerPort = 5001
        protocol      = "tcp"
      }]
      environment = [
        { name = "REDIS_URL", value = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379" },
        { name = "S3_BUCKET", value = aws_s3_bucket.artifacts.bucket },
        { name = "S3_REGION", value = var.aws_region },
        { name = "DATA_DIR", value = "/app/data" },
      ]
      mountPoints = [{
        sourceVolume  = "efs-databases"
        containerPath = "/app/data"
        readOnly      = false
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.adapter.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  volume {
    name = "efs-databases"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.databases.id
      transit_encryption = "ENABLED"
    }
  }

  tags = local.common_tags
}

resource "aws_ecs_service" "adapter" {
  name            = "${local.prefix}-adapter"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.adapter.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.adapter.arn
    container_name   = "adapter"
    container_port   = 5001
  }

  depends_on = [aws_lb_listener.http]
  tags       = local.common_tags
}

resource "aws_cloudwatch_log_group" "adapter" {
  name              = "/ecs/${local.prefix}-adapter"
  retention_in_days = 14
  tags              = local.common_tags
}

# ---------------------------------------------------------------------------
# SQS for background job queues (imports, reports, maintenance, exports)
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "jobs" {
  name                       = "${local.prefix}-jobs"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600
  tags                       = local.common_tags
}

# ---------------------------------------------------------------------------
# ElastiCache Redis for job events and short-lived workspace state
# ---------------------------------------------------------------------------

resource "aws_elasticache_subnet_group" "redis" {
  name        = "${local.prefix}-redis-subnet"
  subnet_ids  = aws_subnet.private[*].id
  description = "Redis subnet group for ${local.prefix}"
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.prefix}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
  tags                 = local.common_tags
}

# ---------------------------------------------------------------------------
# RDS PostgreSQL for users, metadata, permissions, and jobs
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name        = "${local.prefix}-db-subnet"
  subnet_ids  = aws_subnet.private[*].id
  description = "DB subnet group for ${local.prefix}"
  tags        = local.common_tags
}

resource "aws_db_instance" "postgres" {
  identifier             = "${local.prefix}-postgres"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  username               = "scidb"
  password               = "change-me-in-production"
  skip_final_snapshot    = true
  storage_encrypted      = true
  tags                   = local.common_tags
}
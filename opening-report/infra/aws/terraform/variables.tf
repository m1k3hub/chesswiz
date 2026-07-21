###############################################################################
# variables.tf — scidb-beta AWS deployment variables
###############################################################################

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "scidb-beta"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "spa_domain" {
  description = "Custom domain for the SPA (CloudFront distribution)"
  type        = string
  default     = ""
}

variable "api_domain" {
  description = "Custom domain for the API adapter (ALB)"
  type        = string
  default     = ""
}

variable "ecs_cpu" {
  description = "CPU units for the ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "ecs_memory" {
  description = "Memory (MB) for the ECS task"
  type        = number
  default     = 2048
}

variable "ecs_desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 2
}

variable "db_instance_class" {
  description = "RDS PostgreSQL instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS PostgreSQL allocated storage (GB)"
  type        = number
  default     = 20
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "adapter_image" {
  description = "Container image for the runtime adapter"
  type        = string
  default     = "scidb-beta/runtime-adapter:latest"
}
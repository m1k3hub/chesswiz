###############################################################################
# outputs.tf — scidb-beta AWS deployment outputs
###############################################################################

output "cloudfront_distribution_domain" {
  description = "CloudFront domain name for the SPA"
  value       = aws_cloudfront_distribution.spa.domain_name
}

output "spa_s3_bucket" {
  description = "S3 bucket name for SPA static assets"
  value       = aws_s3_bucket.spa.bucket
}

output "artifacts_s3_bucket" {
  description = "S3 bucket name for database files and import artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name for the API adapter"
  value       = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "sqs_jobs_queue_url" {
  description = "SQS queue URL for background jobs"
  value       = aws_sqs_queue.jobs.url
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint address"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
}

output "efs_file_system_id" {
  description = "EFS file system ID for shared database files"
  value       = aws_efs_file_system.databases.id
}
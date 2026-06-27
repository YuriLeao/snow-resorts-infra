output "alb_dns_name" {
  description = "Public DNS of the ALB — create a Route53 alias to your domain here."
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID (for Route53 alias)."
  value       = module.alb.alb_zone_id
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "rds_endpoint" {
  description = "RDS endpoint (host:port)."
  value       = module.rds.endpoint
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master credentials."
  value       = module.rds.master_user_secret_arn
}

output "redis_endpoint" {
  description = "Redis primary endpoint."
  value       = module.redis.primary_endpoint_address
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "ecs_service_names" {
  description = "Names of the ECS services."
  value       = module.ecs.service_names
}

output "s3_bucket_names" {
  description = "Created S3 bucket names."
  value       = module.storage.bucket_names
}

output "cloudfront_domain_names" {
  description = "CloudFront domains per CDN bucket."
  value       = module.storage.cloudfront_domain_names
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN associated with the ALB."
  value       = module.waf.web_acl_arn
}

output "service_connect_namespace" {
  description = "Internal Service Connect DNS namespace (e.g. auth-service.snow.local)."
  value       = module.ecs.service_connect_namespace_name
}

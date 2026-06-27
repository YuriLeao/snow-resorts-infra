output "alb_dns_name" {
  description = "Public DNS of the ALB — point the mobile app / domain here."
  value       = module.alb.alb_dns_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "rds_endpoint" {
  description = "RDS endpoint (host:port)."
  value       = module.rds.endpoint
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "s3_bucket_names" {
  description = "Created S3 bucket names."
  value       = module.storage.bucket_names
}

output "service_connect_namespace" {
  description = "Internal Service Connect DNS namespace."
  value       = module.ecs.service_connect_namespace_name
}

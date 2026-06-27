output "cluster_id" {
  description = "ECS cluster ID."
  value       = aws_ecs_cluster.this.id
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "tasks_security_group_id" {
  description = "Security group attached to the Fargate tasks."
  value       = aws_security_group.tasks.id
}

output "service_connect_namespace_arn" {
  description = "Cloud Map namespace ARN used by Service Connect."
  value       = aws_service_discovery_private_dns_namespace.this.arn
}

output "service_connect_namespace_name" {
  description = "Cloud Map namespace name (internal DNS suffix)."
  value       = aws_service_discovery_private_dns_namespace.this.name
}

output "execution_role_arn" {
  description = "Shared task execution role ARN."
  value       = aws_iam_role.execution.arn
}

output "task_role_arns" {
  description = "Map of service name to task role ARN."
  value       = { for k, r in aws_iam_role.task : k => r.arn }
}

output "service_names" {
  description = "Names of the ECS services created."
  value       = [for s in aws_ecs_service.this : s.name]
}

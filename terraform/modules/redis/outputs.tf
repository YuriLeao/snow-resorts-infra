output "primary_endpoint_address" {
  description = "Primary endpoint address for Redis."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint address (when replicas exist)."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Redis port."
  value       = var.port
}

output "security_group_id" {
  description = "Security group attached to Redis."
  value       = aws_security_group.this.id
}

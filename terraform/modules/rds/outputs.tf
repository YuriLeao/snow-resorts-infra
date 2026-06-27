output "db_instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.this.id
}

output "endpoint" {
  description = "Connection endpoint in address:port form."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "DNS address of the instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Database port."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "Security group attached to the database."
  value       = aws_security_group.this.id
}

output "kms_key_arn" {
  description = "KMS key used for storage encryption."
  value       = local.kms_arn
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN for the RDS-managed master password (null in staging)."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

variable "name_prefix" {
  description = "Prefix applied to all resource names (e.g. snow-resorts-prod)."
  type        = string
}

variable "identifier" {
  description = "RDS instance identifier."
  type        = string
}

variable "vpc_id" {
  description = "VPC the database lives in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group (private in prod, public+restrictive SG in staging)."
  type        = list(string)
}

variable "engine_version" {
  description = "PostgreSQL engine version (16.x for PostGIS support)."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "RDS instance class. db.t4g.micro (staging) / db.t4g.small (prod)."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling in GB (0 disables autoscaling)."
  type        = number
  default     = 0
}

variable "storage_type" {
  description = "Storage type (gp3 recommended)."
  type        = string
  default     = "gp3"
}

variable "multi_az" {
  description = "Enable Multi-AZ (prod). Single-AZ in staging to save cost."
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Name of the initial database. Schemas per service are created by Flyway, not Terraform."
  type        = string
  default     = "snow_resorts"
}

variable "master_username" {
  description = "Master username."
  type        = string
  default     = "snow_admin"
}

variable "master_password" {
  description = "Master password. Provide via SSM (staging) when manage_master_user_password=false. Ignored when manage_master_user_password=true."
  type        = string
  default     = null
  sensitive   = true
}

variable "manage_master_user_password" {
  description = "Let RDS manage the master password in Secrets Manager with automatic rotation (prod)."
  type        = bool
  default     = false
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach the database on the Postgres port (e.g. ECS tasks SG)."
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "Extra CIDR blocks allowed to reach Postgres (use sparingly; keep tight in staging)."
  type        = list(string)
  default     = []
}

variable "port" {
  description = "Postgres port."
  type        = number
  default     = 5432
}

variable "backup_retention_period" {
  description = "Days to retain automated backups."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Protect the instance from accidental deletion (enable in prod)."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (true in staging, false in prod)."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights (prod)."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Existing KMS key ARN for storage encryption. When null a dedicated key is created."
  type        = string
  default     = null
}

variable "shared_preload_libraries" {
  description = "Value for shared_preload_libraries parameter. PostGIS needs no preload; pg_stat_statements is useful."
  type        = string
  default     = "pg_stat_statements"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "name_prefix" {
  description = "Prefix applied to all resource names (e.g. snow-resorts-prod)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster runs in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the ElastiCache subnet group (private subnets in prod)."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach Redis (e.g. ECS tasks SG)."
  type        = list(string)
  default     = []
}

variable "node_type" {
  description = "ElastiCache node type. cache.t4g.micro for MVP."
  type        = string
  default     = "cache.t4g.micro"
}

variable "engine_version" {
  description = "Redis engine version."
  type        = string
  default     = "7.1"
}

variable "port" {
  description = "Redis port."
  type        = number
  default     = 6379
}

variable "num_cache_clusters" {
  description = "Number of nodes in the replication group. 1 = single node (MVP)."
  type        = number
  default     = 1
}

variable "automatic_failover_enabled" {
  description = "Enable automatic failover (requires num_cache_clusters >= 2)."
  type        = bool
  default     = false
}

variable "multi_az_enabled" {
  description = "Enable Multi-AZ (requires num_cache_clusters >= 2)."
  type        = bool
  default     = false
}

variable "at_rest_encryption_enabled" {
  description = "Encrypt data at rest."
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "Encrypt data in transit (TLS)."
  type        = bool
  default     = true
}

variable "snapshot_retention_limit" {
  description = "Days to retain automatic snapshots (0 disables)."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

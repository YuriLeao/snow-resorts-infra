variable "region" {
  description = "AWS region for the production environment."
  type        = string
  default     = "us-east-1"
}

variable "azs" {
  description = "Availability Zones (2 for Multi-AZ RDS and ALB)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (ALB + NAT Gateway)."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (Fargate tasks, RDS, Redis)."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "db_instance_class" {
  description = "RDS instance class for prod."
  type        = string
  default     = "db.t4g.small"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.4"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener (required for prod TLS)."
  type        = string
  default     = null
}

variable "service_images" {
  description = "Container image URI per microservice. Push to ECR before apply."
  type        = map(string)
  default = {
    auth-service     = "public.ecr.aws/docker/library/busybox:latest"
    user-service     = "public.ecr.aws/docker/library/busybox:latest"
    resort-service   = "public.ecr.aws/docker/library/busybox:latest"
    location-service = "public.ecr.aws/docker/library/busybox:latest"
    activity-service = "public.ecr.aws/docker/library/busybox:latest"
  }
}

variable "budget_warning_usd" {
  description = "Monthly cost warning threshold (USD)."
  type        = number
  default     = 150
}

variable "budget_critical_usd" {
  description = "Monthly cost critical threshold (USD)."
  type        = number
  default     = 200
}

variable "budget_alert_emails" {
  description = "Email addresses to notify on budget thresholds."
  type        = list(string)
  default     = []
}

variable "region" {
  description = "AWS region for the staging environment."
  type        = string
  default     = "us-east-1"
}

variable "azs" {
  description = "Availability Zones (2 required for the DB subnet group)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (tasks + RDS live here; no NAT in staging)."
  type        = list(string)
  default     = ["10.10.0.0/24", "10.10.1.0/24"]
}

variable "app_image" {
  description = "Container image for the consolidated staging app (all 5 services in one JVM/process). Push to ECR first."
  type        = string
  default     = "public.ecr.aws/docker/library/busybox:latest"
}

variable "app_container_port" {
  description = "Port the consolidated app listens on."
  type        = number
  default     = 8080
}

variable "db_instance_class" {
  description = "RDS instance class for staging."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.4"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. When null the ALB serves plain HTTP:80 (fine for a closed beta)."
  type        = string
  default     = null
}

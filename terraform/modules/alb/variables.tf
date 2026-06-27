variable "name_prefix" {
  description = "Prefix applied to all resource names (e.g. snow-resorts-prod)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the ALB and target groups live in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets the ALB is attached to."
  type        = list(string)
}

variable "internal" {
  description = "Whether the ALB is internal. Public (false) for client traffic."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener. When null, only an HTTP:80 listener is created (staging without a domain)."
  type        = string
  default     = null
}

variable "ssl_policy" {
  description = "TLS policy for the HTTPS listener (TLS 1.3 capable)."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "ingress_cidr_blocks" {
  description = "CIDRs allowed to reach the ALB on 80/443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "target_groups" {
  description = <<-EOT
    Map of target groups keyed by logical name. Each value:
      - port: container/target port
      - protocol: HTTP (default)
      - health_check_path: path for the health check (default /actuator/health)
      - deregistration_delay: seconds (default 30)
      - stickiness_enabled: enable LB cookie stickiness (true for WSS target)
      - stickiness_duration: cookie duration seconds (default 86400)
  EOT
  type = map(object({
    port                 = number
    protocol             = optional(string, "HTTP")
    health_check_path    = optional(string, "/actuator/health")
    deregistration_delay = optional(number, 30)
    stickiness_enabled   = optional(bool, false)
    stickiness_duration  = optional(number, 86400)
  }))
}

variable "default_target_group_key" {
  description = "Target group that receives traffic not matched by any rule."
  type        = string
}

variable "routing_rules" {
  description = <<-EOT
    Ordered list of path-based routing rules. Each item:
      - target_group_key: key into target_groups
      - path_patterns: list of ALB path patterns (e.g. ["/snow-resort-service/v1/auth/*"])
      - priority: unique listener rule priority (lower = evaluated first)
  EOT
  type = list(object({
    target_group_key = string
    path_patterns    = list(string)
    priority         = number
  }))
  default = []
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion (enable in prod)."
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs (optional)."
  type        = string
  default     = null
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds. Raise for long-lived WebSocket connections."
  type        = number
  default     = 300
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

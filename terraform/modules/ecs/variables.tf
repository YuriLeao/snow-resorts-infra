variable "name_prefix" {
  description = "Prefix applied to all resource names (e.g. snow-resorts-prod)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster runs in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the Fargate tasks. Private subnets in prod; public subnets in staging (no NAT)."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign a public IP to tasks. true in staging (public subnets, no NAT); false in prod (private subnets)."
  type        = bool
  default     = false
}

variable "alb_security_group_id" {
  description = "Security group of the ALB allowed to reach the tasks. null when no ALB fronts the services."
  type        = string
  default     = null
}

variable "additional_security_group_ids" {
  description = <<-EOT
    Extra security groups attached to every task ENI. Used to attach an
    independent "app" SG that RDS/Redis allow as ingress source — this keeps
    least-privilege SG references without creating a cycle (tasks need the DB
    endpoint, so the DB must not depend on the module-managed tasks SG).
  EOT
  type        = list(string)
  default     = []
}

variable "service_connect_namespace" {
  description = "Private DNS namespace for Cloud Map / ECS Service Connect (e.g. snow.local)."
  type        = string
  default     = "snow.local"
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights on the cluster."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 30
}

variable "region" {
  description = "AWS region (used for awslogs driver). Defaults to the provider region when null."
  type        = string
  default     = null
}

variable "services" {
  description = <<-EOT
    Map of ECS services keyed by service name (e.g. auth-service). Each value:
      - image: container image URI
      - container_port: port the app listens on
      - cpu / memory: Fargate task size (256/512 for MVP)
      - desired_count: number of tasks
      - command: optional container command override
      - health_check_path: container health check path (default /actuator/health)
      - target_group_arn: ALB target group to attach (null = internal-only service)
      - use_fargate_spot: run on Fargate Spot (resort-service only)
      - environment: plain env vars (map)
      - secrets: name -> SSM Parameter / Secrets Manager ARN (injected as env)
      - task_role_policy_json: least-privilege IAM policy for the task role (null = no extra perms)
      - enable_service_connect: register this service in the namespace for service->service discovery
      - enable_execute_command: allow ECS Exec (debugging)
      - autoscaling: optional { min_capacity, max_capacity, cpu_target, memory_target }
        location-service (connection-based scaling) can layer a custom-metric
        policy on top of the target created here.
  EOT
  type = map(object({
    image                  = string
    container_port         = number
    cpu                    = number
    memory                 = number
    desired_count          = optional(number, 1)
    command                = optional(list(string))
    health_check_path      = optional(string, "/actuator/health")
    target_group_arn       = optional(string)
    use_fargate_spot       = optional(bool, false)
    environment            = optional(map(string), {})
    secrets                = optional(map(string), {})
    task_role_policy_json  = optional(string)
    enable_service_connect = optional(bool, true)
    enable_execute_command = optional(bool, false)
    autoscaling = optional(object({
      min_capacity  = number
      max_capacity  = number
      cpu_target    = optional(number)
      memory_target = optional(number)
    }))
  }))
}

variable "execution_secret_arns" {
  description = <<-EOT
    Base ARNs of SSM Parameters / Secrets Manager secrets the task execution
    role may read to inject the `secrets` values. Pass the BASE secret ARN here
    (without any ":jsonkey::" suffix used in the container `secrets` valueFrom).
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

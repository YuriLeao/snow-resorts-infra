# =============================================================================
# PROD — full architecture (~$120-200/mo)
#   * 2 AZs, single NAT Gateway, private subnets for tasks/RDS/Redis
#   * S3 Gateway + ECR/Logs/Secrets/SSM interface endpoints (cut NAT traffic)
#   * 5 Fargate services + Service Connect; resort-service on Fargate Spot
#   * Single ALB, path-based routing, WSS stickiness on location target group
#   * ElastiCache Redis, WAF (Common Rule Set + 2000/5min rate limit)
#   * Multi-AZ RDS db.t4g.small, RDS-managed (rotated) master password
#   * S3 (KMS) + CloudFront; AWS Budgets at $150 / $200
# =============================================================================

locals {
  name_prefix    = "snow-resorts-prod"
  container_port = 8080

  tags = {
    Project     = "snow-resorts"
    Environment = "prod"
  }
}

data "aws_caller_identity" "current" {}

# --- KMS key for S3 at-rest encryption ---
resource "aws_kms_key" "data" {
  description             = "${local.name_prefix} S3 data encryption"
  deletion_window_in_days = 14
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_kms_alias" "data" {
  name          = "alias/${local.name_prefix}-data"
  target_key_id = aws_kms_key.data.key_id
}

# --- JWT signing secret (Secrets Manager) ---
resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "jwt" {
  name        = "${local.name_prefix}/auth/jwt-secret"
  description = "JWT signing secret for auth-service"
  kms_key_id  = aws_kms_key.data.arn
  tags        = local.tags
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = random_password.jwt.result
}

# NOTE: JWT secret rotation requires a rotation Lambda. The RDS master password
# IS rotated automatically (manage_master_user_password below). To rotate the
# JWT secret, attach an aws_secretsmanager_secret_rotation with a rotation
# Lambda; left out here because no Lambda packaging exists in this repo scope.

# --- Networking: 2 AZs, single NAT, private subnets, VPC endpoints ---
module "vpc" {
  source = "../../modules/vpc"

  name_prefix          = local.name_prefix
  cidr_block           = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  enable_nat_gateway         = true
  single_nat_gateway         = true # one NAT to save cost (~$32/mo vs 2x)
  enable_s3_gateway_endpoint = true
  enable_interface_endpoints = true # ECR/Logs/Secrets/SSM — reduce NAT traffic

  tags = local.tags
}

# Independent "app" SG attached to tasks; allowed by RDS and Redis.
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "Marker SG for app tasks to reach data stores"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-app-sg" })
}

# --- Storage: S3 (KMS) + CloudFront ---
module "storage" {
  source = "../../modules/s3-cloudfront"

  name_prefix       = local.name_prefix
  enable_cloudfront = true
  kms_key_arn       = aws_kms_key.data.arn

  tags = local.tags
}

# --- Database: db.t4g.small Multi-AZ, managed rotated password ---
module "rds" {
  source = "../../modules/rds"

  name_prefix    = local.name_prefix
  identifier     = "${local.name_prefix}-pg"
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage     = 30
  max_allocated_storage = 100
  storage_type          = "gp3"
  multi_az              = true

  manage_master_user_password = true # Secrets Manager managed + auto-rotated

  allowed_security_group_ids = [aws_security_group.app.id]

  backup_retention_period      = 7
  deletion_protection          = true
  skip_final_snapshot          = false
  performance_insights_enabled = true

  tags = local.tags
}

# --- Redis: ElastiCache cache.t4g.micro ---
module "redis" {
  source = "../../modules/redis"

  name_prefix                = local.name_prefix
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [aws_security_group.app.id]
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 1

  tags = local.tags
}

# --- ALB: single ALB, 5 target groups, path routing, WSS stickiness ---
module "alb" {
  source = "../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = var.certificate_arn

  target_groups = {
    auth     = { port = local.container_port }
    user     = { port = local.container_port }
    resort   = { port = local.container_port }
    location = { port = local.container_port, stickiness_enabled = true }
    activity = { port = local.container_port }
  }

  default_target_group_key = "auth"

  routing_rules = [
    { target_group_key = "auth", path_patterns = ["/snow-resort-service/v1/auth/*"], priority = 10 },
    { target_group_key = "user", path_patterns = ["/snow-resort-service/v1/users/*"], priority = 20 },
    { target_group_key = "user", path_patterns = ["/snow-resort-service/v1/friends/*"], priority = 21 },
    { target_group_key = "resort", path_patterns = ["/snow-resort-service/v1/resorts/*"], priority = 30 },
    { target_group_key = "location", path_patterns = ["/snow-resort-service/v1/location/*"], priority = 40 },
    { target_group_key = "location", path_patterns = ["/ws/*"], priority = 41 },
    { target_group_key = "activity", path_patterns = ["/snow-resort-service/v1/runs/*"], priority = 50 },
    { target_group_key = "activity", path_patterns = ["/snow-resort-service/v1/leaderboard/*"], priority = 51 },

    # --- Unified Swagger UI (mirrors local docker/nginx; see terraform/README.md) ---
    # Enable once a `docs` target group backed by a swaggerapi/swagger-ui task exists.
    # NOTE: the ALB does path routing but NO path rewrite, so `/api-docs/<svc>` cannot be
    # rewritten to `/v3/api-docs` here — either front it with an nginx sidecar (option 1)
    # or set each service's springdoc.api-docs.path to `/api-docs/<svc>` (option 2).
    # { target_group_key = "docs",     path_patterns = ["/swagger", "/swagger/*"],   priority = 5 },
    # { target_group_key = "auth",     path_patterns = ["/api-docs/auth"],           priority = 6 },
    # { target_group_key = "user",     path_patterns = ["/api-docs/user"],           priority = 7 },
    # { target_group_key = "resort",   path_patterns = ["/api-docs/resort"],         priority = 8 },
    # { target_group_key = "location", path_patterns = ["/api-docs/location"],       priority = 9 },
    # { target_group_key = "activity", path_patterns = ["/api-docs/activity"],       priority = 12 },
  ]

  enable_deletion_protection = true

  tags = local.tags
}

# --- WAF on the ALB ---
module "waf" {
  source = "../../modules/waf"

  name_prefix            = local.name_prefix
  scope                  = "REGIONAL"
  rate_limit             = 2000
  associate_resource_arn = module.alb.alb_arn

  tags = local.tags
}

# --- Per-service least-privilege task role policies ---
data "aws_iam_policy_document" "user_task" {
  statement {
    sid       = "AvatarsRW"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${module.storage.bucket_arns["avatars"]}/*"]
  }
  statement {
    sid       = "AssetsRead"
    actions   = ["s3:GetObject"]
    resources = ["${module.storage.bucket_arns["assets"]}/*"]
  }
  statement {
    sid       = "KmsForS3"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.data.arn]
  }
}

data "aws_iam_policy_document" "resort_task" {
  statement {
    sid       = "MapPackagesRW"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${module.storage.bucket_arns["map-packages"]}/*"]
  }
  statement {
    sid       = "AssetsRead"
    actions   = ["s3:GetObject"]
    resources = ["${module.storage.bucket_arns["assets"]}/*"]
  }
  statement {
    sid       = "KmsForS3"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.data.arn]
  }
}

data "aws_iam_policy_document" "activity_task" {
  statement {
    sid       = "TracksRW"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${module.storage.bucket_arns["tracks"]}/*"]
  }
  statement {
    sid       = "KmsForS3"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.data.arn]
  }
}

locals {
  # Common env injected into every service.
  common_env = {
    DB_HOST     = module.rds.address
    DB_PORT     = tostring(module.rds.port)
    DB_NAME     = module.rds.db_name
    DB_USERNAME = "snow_admin"
    REDIS_HOST  = module.redis.primary_endpoint_address
    REDIS_PORT  = tostring(module.redis.port)
    REDIS_SSL   = "true"

    S3_BUCKET_ASSETS       = module.storage.bucket_names["assets"]
    S3_BUCKET_AVATARS      = module.storage.bucket_names["avatars"]
    S3_BUCKET_MAP_PACKAGES = module.storage.bucket_names["map-packages"]
    S3_BUCKET_TRACKS       = module.storage.bucket_names["tracks"]

    SPRING_PROFILES_ACTIVE = "prod"
  }

  # Secrets injected into every service. DB password comes from the RDS-managed
  # Secrets Manager secret (JSON), JWT from the dedicated secret.
  common_secrets = {
    DB_PASSWORD = "${module.rds.master_user_secret_arn}:password::"
    JWT_SECRET  = aws_secretsmanager_secret.jwt.arn
  }
}

# --- Compute: 5 Fargate services + Service Connect ---
module "ecs" {
  source = "../../modules/ecs"

  name_prefix                   = local.name_prefix
  vpc_id                        = module.vpc.vpc_id
  subnet_ids                    = module.vpc.private_subnet_ids
  assign_public_ip              = false
  alb_security_group_id         = module.alb.alb_security_group_id
  additional_security_group_ids = [aws_security_group.app.id]
  service_connect_namespace     = "snow.local"
  enable_container_insights     = true
  log_retention_days            = 30

  execution_secret_arns = [
    module.rds.master_user_secret_arn,
    aws_secretsmanager_secret.jwt.arn,
  ]

  services = {
    auth-service = {
      image            = var.service_images["auth-service"]
      container_port   = local.container_port
      cpu              = 256
      memory           = 512
      desired_count    = 1
      target_group_arn = module.alb.target_group_arns["auth"]
      environment      = local.common_env
      secrets          = local.common_secrets
    }

    user-service = {
      image            = var.service_images["user-service"]
      container_port   = local.container_port
      cpu              = 256
      memory           = 512
      desired_count    = 1
      target_group_arn = module.alb.target_group_arns["user"]
      environment      = local.common_env
      secrets          = local.common_secrets

      task_role_policy_json = data.aws_iam_policy_document.user_task.json
    }

    resort-service = {
      image            = var.service_images["resort-service"]
      container_port   = local.container_port
      cpu              = 256
      memory           = 512
      desired_count    = 1
      target_group_arn = module.alb.target_group_arns["resort"]
      use_fargate_spot = true # read-heavy, interruption-tolerant
      environment      = local.common_env
      secrets          = local.common_secrets

      task_role_policy_json = data.aws_iam_policy_document.resort_task.json

      autoscaling = {
        min_capacity = 1
        max_capacity = 3
        cpu_target   = 60
      }
    }

    location-service = {
      image            = var.service_images["location-service"]
      container_port   = local.container_port
      cpu              = 256
      memory           = 512
      desired_count    = 1
      target_group_arn = module.alb.target_group_arns["location"]
      environment      = local.common_env
      secrets          = local.common_secrets

      # location scales by connections; CPU target tracking as a baseline.
      autoscaling = {
        min_capacity = 1
        max_capacity = 3
        cpu_target   = 60
      }
    }

    activity-service = {
      image            = var.service_images["activity-service"]
      container_port   = local.container_port
      cpu              = 256
      memory           = 512
      desired_count    = 1
      target_group_arn = module.alb.target_group_arns["activity"]
      environment      = local.common_env
      secrets          = local.common_secrets

      task_role_policy_json = data.aws_iam_policy_document.activity_task.json

      autoscaling = {
        min_capacity = 1
        max_capacity = 3
        cpu_target   = 70
      }
    }
  }

  tags = local.tags
}

# --- AWS Budgets ---
resource "aws_budgets_budget" "warning" {
  name         = "${local.name_prefix}-monthly-warning"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_warning_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = length(var.budget_alert_emails) > 0 ? [1] : []
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = 100
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.budget_alert_emails
    }
  }
}

resource "aws_budgets_budget" "critical" {
  name         = "${local.name_prefix}-monthly-critical"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_critical_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = length(var.budget_alert_emails) > 0 ? [1] : []
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = 100
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.budget_alert_emails
    }
  }

  dynamic "notification" {
    for_each = length(var.budget_alert_emails) > 0 ? [1] : []
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = 80
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = var.budget_alert_emails
    }
  }
}

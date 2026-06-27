# =============================================================================
# STAGING — cost-optimized beta (~$42-55/mo)
#   * Public subnets only, NO NAT Gateway (saves ~$32/mo)
#   * Single RDS db.t4g.micro, Single-AZ
#   * ONE Fargate task running the consolidated app (all 5 services in 1 JVM)
#   * Single ALB with path routing (WSS stickiness on the app target group)
#   * NO Redis (WebSocket fanout in-memory on the single task) — see note below
#   * NO WAF, NO CloudFront (presigned URLs straight to S3)
#   * Secrets in SSM Parameter Store (free) instead of Secrets Manager
# =============================================================================

locals {
  name_prefix = "snow-resorts-staging"

  tags = {
    Project     = "snow-resorts"
    Environment = "staging"
  }
}

data "aws_caller_identity" "current" {}

# --- Secrets (SSM Parameter Store — free tier vs Secrets Manager) ---
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name        = "/${local.name_prefix}/db/password"
  description = "RDS master password (staging)"
  type        = "SecureString"
  value       = random_password.db.result
  tags        = local.tags
}

resource "aws_ssm_parameter" "jwt_secret" {
  name        = "/${local.name_prefix}/auth/jwt-secret"
  description = "JWT signing secret (staging)"
  type        = "SecureString"
  value       = random_password.jwt.result
  tags        = local.tags
}

# --- Networking: public subnets only, no NAT ---
module "vpc" {
  source = "../../modules/vpc"

  name_prefix         = local.name_prefix
  cidr_block          = var.vpc_cidr
  azs                 = var.azs
  public_subnet_cidrs = var.public_subnet_cidrs

  enable_nat_gateway         = false
  enable_s3_gateway_endpoint = true  # free, keeps S3 traffic off the public path
  enable_interface_endpoints = false # interface endpoints cost ~$7/mo each — skip in staging

  tags = local.tags
}

# Independent "app" SG: attached to tasks and allowed by RDS. Keeps SG-based
# least privilege without an ECS<->RDS dependency cycle.
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

# --- Data: S3 buckets (no CloudFront in staging) ---
module "storage" {
  source = "../../modules/s3-cloudfront"

  name_prefix       = local.name_prefix
  enable_cloudfront = false # presigned URLs direct to S3
  kms_key_arn       = null  # SSE-S3 (AES256) to avoid KMS cost in staging

  tags = local.tags
}

# --- Database: db.t4g.micro Single-AZ ---
module "rds" {
  source = "../../modules/rds"

  name_prefix    = local.name_prefix
  identifier     = "${local.name_prefix}-pg"
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.public_subnet_ids
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = 20
  multi_az          = false

  manage_master_user_password = false
  master_password             = random_password.db.result

  allowed_security_group_ids = [aws_security_group.app.id]

  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = local.tags
}

# --- ALB: single target group, all paths to the consolidated app ---
module "alb" {
  source = "../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  certificate_arn   = var.certificate_arn

  target_groups = {
    app = {
      port              = var.app_container_port
      health_check_path = "/actuator/health"
      # Stickiness on so /ws/* WebSocket sessions stay pinned to a task.
      stickiness_enabled  = true
      stickiness_duration = 86400
    }
  }

  default_target_group_key = "app"

  # All documented routes resolve to the single app target group in staging.
  routing_rules = [
    { target_group_key = "app", path_patterns = ["/snow-resort-service/v1/*"], priority = 10 },
    { target_group_key = "app", path_patterns = ["/ws/*"], priority = 20 },

    # Unified Swagger UI: in staging everything already falls through to the single `app`
    # target group (default_target_group_key = "app"), so `/swagger/*` and `/api-docs/*`
    # reach the app task. Provision a swaggerapi/swagger-ui container in that task (or a
    # `docs` target group) to actually serve them — see terraform/README.md. Intended rules:
    # { target_group_key = "app", path_patterns = ["/swagger", "/swagger/*"], priority = 5 },
    # { target_group_key = "app", path_patterns = ["/api-docs/*"], priority = 6 },
  ]

  enable_deletion_protection = false

  tags = local.tags
}

# --- Compute: ONE Fargate task running all services ---
data "aws_iam_policy_document" "app_task" {
  statement {
    sid     = "AppS3Access"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "${module.storage.bucket_arns["assets"]}/*",
      "${module.storage.bucket_arns["avatars"]}/avatars/*",
      "${module.storage.bucket_arns["map-packages"]}/*",
      "${module.storage.bucket_arns["tracks"]}/*",
    ]
  }
}

module "ecs" {
  source = "../../modules/ecs"

  name_prefix                   = local.name_prefix
  vpc_id                        = module.vpc.vpc_id
  subnet_ids                    = module.vpc.public_subnet_ids
  assign_public_ip              = true # public subnet, no NAT — needs a public IP to pull images
  alb_security_group_id         = module.alb.alb_security_group_id
  additional_security_group_ids = [aws_security_group.app.id]
  service_connect_namespace     = "snow-staging.local"
  log_retention_days            = 14
  enable_container_insights     = false

  execution_secret_arns = [
    aws_ssm_parameter.db_password.arn,
    aws_ssm_parameter.jwt_secret.arn,
  ]

  services = {
    app = {
      image             = var.app_image
      container_port    = var.app_container_port
      cpu               = 512
      memory            = 1024
      desired_count     = 1
      target_group_arn  = module.alb.target_group_arns["app"]
      health_check_path = "/actuator/health"

      environment = {
        SPRING_PROFILES_ACTIVE = "staging"
        DB_HOST                = module.rds.address
        DB_PORT                = tostring(module.rds.port)
        DB_NAME                = module.rds.db_name
        DB_USERNAME            = "snow_admin"
        S3_BUCKET_ASSETS       = module.storage.bucket_names["assets"]
        S3_BUCKET_AVATARS      = module.storage.bucket_names["avatars"]
        S3_BUCKET_MAP_PACKAGES = module.storage.bucket_names["map-packages"]
        S3_BUCKET_TRACKS       = module.storage.bucket_names["tracks"]
        REDIS_ENABLED          = "false" # no ElastiCache in staging; in-memory fanout
      }

      secrets = {
        DB_PASSWORD = aws_ssm_parameter.db_password.arn
        JWT_SECRET  = aws_ssm_parameter.jwt_secret.arn
      }

      task_role_policy_json  = data.aws_iam_policy_document.app_task.json
      enable_service_connect = true
    }
  }

  tags = local.tags
}

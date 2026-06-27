# PostgreSQL 16 + PostGIS. PostGIS is enabled per-schema via Flyway/SQL
# (CREATE EXTENSION postgis;) on first migration. RDS for PostgreSQL supports
# PostGIS natively. NOTE: TimescaleDB is NOT available on standard RDS Postgres;
# the activity-service gps_points hypertable strategy must use native Postgres
# partitioning on RDS, or move to Aurora/self-managed if TimescaleDB is required.

locals {
  create_kms = var.kms_key_arn == null
  kms_arn    = local.create_kms ? aws_kms_key.this[0].arn : var.kms_key_arn

  engine_family = "postgres${split(".", var.engine_version)[0]}"
}

resource "aws_kms_key" "this" {
  count = local.create_kms ? 1 : 0

  description             = "${var.name_prefix} RDS storage encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-kms" })
}

resource "aws_kms_alias" "this" {
  count = local.create_kms ? 1 : 0

  name          = "alias/${var.name_prefix}-rds"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-db-subnets" })
}

resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Postgres access for ${var.name_prefix}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-sg" })
}

resource "aws_security_group_rule" "ingress_sg" {
  count = length(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.this.id
  source_security_group_id = var.allowed_security_group_ids[count.index]
  description              = "Postgres from allowed security group"
}

resource "aws_security_group_rule" "ingress_cidr" {
  count = length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  security_group_id = aws_security_group.this.id
  cidr_blocks       = var.allowed_cidr_blocks
  description       = "Postgres from allowed CIDRs"
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.this.id
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound"
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.name_prefix}-pg"
  family      = local.engine_family
  description = "Parameter group for ${var.name_prefix} PostgreSQL"

  parameter {
    name  = "shared_preload_libraries"
    value = var.shared_preload_libraries
    # shared_preload_libraries requires an instance reboot to take effect.
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = local.kms_arn

  db_name  = var.db_name
  username = var.master_username

  # Either RDS-managed secret (prod, rotated) or an explicit password (staging via SSM).
  manage_master_user_password   = var.manage_master_user_password ? true : null
  master_user_secret_kms_key_id = var.manage_master_user_password ? local.kms_arn : null
  password                      = var.manage_master_user_password ? null : var.master_password

  multi_az                  = var.multi_az
  port                      = var.port
  db_subnet_group_name      = aws_db_subnet_group.this.name
  vpc_security_group_ids    = [aws_security_group.this.id]
  parameter_group_name      = aws_db_parameter_group.this.name
  backup_retention_period   = var.backup_retention_period
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final"

  publicly_accessible          = false
  performance_insights_enabled = var.performance_insights_enabled
  auto_minor_version_upgrade   = true
  copy_tags_to_snapshot        = true

  tags = merge(var.tags, { Name = var.identifier })
}

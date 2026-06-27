data "aws_region" "current" {}

locals {
  region = coalesce(var.region, data.aws_region.current.name)

  all_secret_arns = distinct(var.execution_secret_arns)

  services_with_asg = { for k, v in var.services : k => v if v.autoscaling != null }
}

# --- Cluster + capacity providers ---
resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-cluster" })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# --- Cloud Map namespace for ECS Service Connect ---
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = var.service_connect_namespace
  description = "Service Connect namespace for ${var.name_prefix}"
  vpc         = var.vpc_id

  tags = var.tags
}

# --- Security group for the tasks ---
resource "aws_security_group" "tasks" {
  name        = "${var.name_prefix}-ecs-tasks-sg"
  description = "ECS Fargate tasks for ${var.name_prefix}"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-tasks-sg" })
}

# Allow the ALB to reach the task ports.
resource "aws_security_group_rule" "from_alb" {
  count = var.alb_security_group_id != null ? 1 : 0

  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.tasks.id
  source_security_group_id = var.alb_security_group_id
  description              = "Traffic from the ALB"
}

# Allow task-to-task traffic for Service Connect.
resource "aws_security_group_rule" "intra" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = aws_security_group.tasks.id
  self              = true
  description       = "Intra-cluster Service Connect traffic"
}

# --- Shared task execution role (pull image, write logs, read secrets) ---
data "aws_iam_policy_document" "execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.execution_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  count = length(local.all_secret_arns) > 0 ? 1 : 0

  statement {
    sid       = "ReadSecrets"
    actions   = ["secretsmanager:GetSecretValue", "ssm:GetParameters", "ssm:GetParameter"]
    resources = local.all_secret_arns
  }

  statement {
    sid       = "DecryptSecrets"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = length(local.all_secret_arns) > 0 ? 1 : 0

  name   = "${var.name_prefix}-ecs-execution-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

# --- Per-service task roles (least privilege) ---
resource "aws_iam_role" "task" {
  for_each = var.services

  name               = "${var.name_prefix}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.execution_assume.json
  tags               = merge(var.tags, { Service = each.key })
}

resource "aws_iam_role_policy" "task" {
  for_each = { for k, v in var.services : k => v if v.task_role_policy_json != null }

  name   = "${var.name_prefix}-${each.key}-task-policy"
  role   = aws_iam_role.task[each.key].id
  policy = each.value.task_role_policy_json
}

# Allow ECS Exec where enabled.
data "aws_iam_policy_document" "exec_command" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "exec_command" {
  for_each = { for k, v in var.services : k => v if v.enable_execute_command }

  name   = "${var.name_prefix}-${each.key}-exec"
  role   = aws_iam_role.task[each.key].id
  policy = data.aws_iam_policy_document.exec_command.json
}

# --- Log groups ---
resource "aws_cloudwatch_log_group" "this" {
  for_each = var.services

  name              = "/ecs/${var.name_prefix}/${each.key}"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, { Service = each.key })
}

# --- Task definitions ---
resource "aws_ecs_task_definition" "this" {
  for_each = var.services

  family                   = "${var.name_prefix}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task[each.key].arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = each.value.image
      essential = true
      command   = each.value.command

      portMappings = [
        {
          name          = "app"
          containerPort = each.value.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for k, v in each.value.environment : { name = k, value = v }
      ]

      secrets = [
        for k, v in each.value.secrets : { name = k, valueFrom = v }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this[each.key].name
          "awslogs-region"        = local.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(var.tags, { Service = each.key })
}

# --- Services ---
resource "aws_ecs_service" "this" {
  for_each = var.services

  name            = each.key
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.desired_count

  enable_execute_command = each.value.enable_execute_command

  capacity_provider_strategy {
    capacity_provider = each.value.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = concat([aws_security_group.tasks.id], var.additional_security_group_ids)
    assign_public_ip = var.assign_public_ip
  }

  service_connect_configuration {
    enabled   = each.value.enable_service_connect
    namespace = aws_service_discovery_private_dns_namespace.this.arn

    dynamic "service" {
      for_each = each.value.enable_service_connect ? [1] : []
      content {
        port_name      = "app"
        discovery_name = each.key
        client_alias {
          port     = each.value.container_port
          dns_name = each.key
        }
      }
    }
  }

  dynamic "load_balancer" {
    for_each = each.value.target_group_arn != null ? [1] : []
    content {
      target_group_arn = each.value.target_group_arn
      container_name   = each.key
      container_port   = each.value.container_port
    }
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [desired_count] # managed by autoscaling when enabled
  }

  tags = merge(var.tags, { Service = each.key })
}

# --- Auto scaling (optional per service) ---
resource "aws_appautoscaling_target" "this" {
  for_each = local.services_with_asg

  max_capacity       = each.value.autoscaling.max_capacity
  min_capacity       = each.value.autoscaling.min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = { for k, v in local.services_with_asg : k => v if v.autoscaling.cpu_target != null }

  name               = "${var.name_prefix}-${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = each.value.autoscaling.cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "memory" {
  for_each = { for k, v in local.services_with_asg : k => v if v.autoscaling.memory_target != null }

  name               = "${var.name_prefix}-${each.key}-mem"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = each.value.autoscaling.memory_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

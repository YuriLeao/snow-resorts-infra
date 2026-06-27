locals {
  has_https = var.certificate_arn != null
}

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Public ingress for the ${var.name_prefix} ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = local.has_https ? [1] : []
    content {
      description = "HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.ingress_cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-sg" })
}

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = var.idle_timeout
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != null ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.name_prefix
      enabled = true
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb" })
}

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name        = "${var.name_prefix}-${each.key}-tg"
  port        = each.value.port
  protocol    = each.value.protocol
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate awsvpc networking

  deregistration_delay = each.value.deregistration_delay

  health_check {
    enabled             = true
    path                = each.value.health_check_path
    protocol            = each.value.protocol
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  dynamic "stickiness" {
    for_each = each.value.stickiness_enabled ? [1] : []
    content {
      type            = "lb_cookie"
      cookie_duration = each.value.stickiness_duration
      enabled         = true
    }
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}-tg" })

  lifecycle {
    create_before_destroy = true
  }
}

# --- Listeners ---
# When a certificate is provided: HTTP:80 redirects to HTTPS:443 and the
# default action / routing rules live on the HTTPS listener.
# Without a certificate (staging, no domain): HTTP:80 carries the routing.

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.has_https ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.has_https ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this[var.default_target_group_key].arn
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.has_https ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[var.default_target_group_key].arn
  }
}

locals {
  routed_listener_arn = local.has_https ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}

resource "aws_lb_listener_rule" "path" {
  for_each = { for rule in var.routing_rules : tostring(rule.priority) => rule }

  listener_arn = local.routed_listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.target_group_key].arn
  }

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }

  tags = var.tags
}

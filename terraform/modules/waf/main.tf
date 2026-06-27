resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name_prefix}-web-acl"
  description = "WAF for ${var.name_prefix} (managed rules + rate limit)"
  scope       = var.scope

  default_action {
    allow {}
  }

  # AWS Managed Common Rule Set (OWASP-style protections).
  dynamic "rule" {
    for_each = var.enable_common_rule_set ? [1] : []
    content {
      name     = "AWSManagedRulesCommonRuleSet"
      priority = 1

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesCommonRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-common"
        sampled_requests_enabled   = true
      }
    }
  }

  # Known bad inputs.
  dynamic "rule" {
    for_each = var.enable_known_bad_inputs ? [1] : []
    content {
      name     = "AWSManagedRulesKnownBadInputs"
      priority = 2

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name_prefix}-bad-inputs"
        sampled_requests_enabled   = true
      }
    }
  }

  # Rate-based rule: block IPs over the limit per 5 minutes.
  rule {
    name     = "RateLimit"
    priority = 10

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.associate_resource_arn != null ? 1 : 0

  resource_arn = var.associate_resource_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

data "aws_caller_identity" "current" {}

locals {
  suffix      = coalesce(var.bucket_suffix, data.aws_caller_identity.current.account_id)
  sse_kms     = var.kms_key_arn != null
  cdn_buckets = var.enable_cloudfront ? { for k, v in var.buckets : k => v if v.cdn } : {}

  bucket_names = { for k, v in var.buckets : k => "${var.name_prefix}-${k}-${local.suffix}" }
}

resource "aws_s3_bucket" "this" {
  for_each = var.buckets

  bucket = local.bucket_names[each.key]

  tags = merge(var.tags, { Name = local.bucket_names[each.key], Bucket = each.key })
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = { for k, v in var.buckets : k => v if v.versioning }

  bucket = aws_s3_bucket.this[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.sse_kms ? var.kms_key_arn : null
    }
    bucket_key_enabled = local.sse_kms
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = { for k, v in var.buckets : k => v if v.glacier_after_days > 0 }

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    id     = "archive-to-glacier"
    status = "Enabled"

    filter {}

    transition {
      days          = each.value.glacier_after_days
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "HEAD"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# --- CloudFront (per CDN bucket) ---
resource "aws_cloudfront_origin_access_control" "this" {
  for_each = local.cdn_buckets

  name                              = "${var.name_prefix}-${each.key}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  for_each = local.cdn_buckets

  enabled             = true
  comment             = "${var.name_prefix} ${each.key}"
  price_class         = var.cloudfront_price_class
  default_root_object = ""

  origin {
    domain_name              = aws_s3_bucket.this[each.key].bucket_regional_domain_name
    origin_id                = "s3-${each.key}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this[each.key].id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-${each.key}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    # AWS managed "CachingOptimized" policy.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}-cdn" })
}

# Bucket policy granting the CloudFront distribution read access via OAC.
data "aws_iam_policy_document" "cdn" {
  for_each = local.cdn_buckets

  statement {
    sid       = "AllowCloudFrontServicePrincipal"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this[each.key].arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this[each.key].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cdn" {
  for_each = local.cdn_buckets

  bucket = aws_s3_bucket.this[each.key].id
  policy = data.aws_iam_policy_document.cdn[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

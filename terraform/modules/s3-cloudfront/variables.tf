variable "name_prefix" {
  description = "Prefix applied to all resource names (e.g. snow-resorts-prod)."
  type        = string
}

variable "bucket_suffix" {
  description = "Suffix to make bucket names globally unique (e.g. AWS account id). When null the caller account id is used."
  type        = string
  default     = null
}

variable "buckets" {
  description = <<-EOT
    Map of logical bucket name to config:
      - cdn: serve this bucket through CloudFront (public read via OAC)
      - glacier_after_days: transition objects to Glacier after N days (0 disables)
      - versioning: enable bucket versioning
  EOT
  type = map(object({
    cdn                = optional(bool, false)
    glacier_after_days = optional(number, 0)
    versioning         = optional(bool, false)
  }))
  default = {
    assets         = { cdn = true, versioning = true }
    avatars        = { cdn = true, versioning = true }
    "map-packages" = { cdn = true, versioning = true }
    tracks         = { cdn = false, glacier_after_days = 365, versioning = false }
  }
}

variable "enable_cloudfront" {
  description = "Create CloudFront distributions for CDN buckets. Disabled in staging (presigned URLs direct to S3)."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for SSE-KMS at rest. When null, SSE-S3 (AES256) is used."
  type        = string
  default     = null
}

variable "cloudfront_price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "cors_allowed_origins" {
  description = "Allowed origins for S3 CORS (presigned PUT from the mobile app)."
  type        = list(string)
  default     = ["*"]
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

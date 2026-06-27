variable "name_prefix" {
  description = "Prefix applied to all resource names (e.g. snow-resorts-prod)."
  type        = string
}

variable "scope" {
  description = "WAF scope. REGIONAL for ALB; CLOUDFRONT for CloudFront (must be us-east-1)."
  type        = string
  default     = "REGIONAL"
}

variable "rate_limit" {
  description = "Requests per 5 minutes per IP before blocking."
  type        = number
  default     = 2000
}

variable "associate_resource_arn" {
  description = "ARN of the resource (ALB) to associate the Web ACL with. null skips association."
  type        = string
  default     = null
}

variable "enable_common_rule_set" {
  description = "Enable AWSManagedRulesCommonRuleSet."
  type        = bool
  default     = true
}

variable "enable_known_bad_inputs" {
  description = "Enable AWSManagedRulesKnownBadInputsRuleSet."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

output "bucket_names" {
  description = "Map of logical name to actual S3 bucket name."
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}

output "bucket_arns" {
  description = "Map of logical name to S3 bucket ARN."
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}

output "cloudfront_domain_names" {
  description = "Map of CDN bucket to CloudFront domain name."
  value       = { for k, d in aws_cloudfront_distribution.this : k => d.domain_name }
}

output "cloudfront_distribution_ids" {
  description = "Map of CDN bucket to CloudFront distribution ID."
  value       = { for k, d in aws_cloudfront_distribution.this : k => d.id }
}

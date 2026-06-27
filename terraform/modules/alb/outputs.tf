output "alb_arn" {
  description = "ARN of the Application Load Balancer."
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "Public DNS name of the ALB."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the ALB (for Route53 alias records)."
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  description = "Security group attached to the ALB."
  value       = aws_security_group.alb.id
}

output "target_group_arns" {
  description = "Map of target group key to ARN."
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (null when no certificate)."
  value       = try(aws_lb_listener.https[0].arn, null)
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener."
  value       = aws_lb_listener.http.arn
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (empty when not created)."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways (empty when disabled)."
  value       = aws_nat_gateway.this[*].id
}

output "s3_endpoint_id" {
  description = "ID of the S3 Gateway VPC endpoint (null when disabled)."
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

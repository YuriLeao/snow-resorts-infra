variable "name_prefix" {
  description = "Prefix applied to all resource names (e.g. snow-resorts-prod)."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones to spread subnets across (2 recommended)."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets (one per AZ). Empty disables private subnets (staging cost-saving)."
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway so private subnets reach the internet. Disabled in staging to save ~$32/mo."
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT Gateway across AZs instead of one per AZ (cost optimization)."
  type        = bool
  default     = true
}

variable "enable_s3_gateway_endpoint" {
  description = "Create the free S3 Gateway VPC endpoint to keep S3 traffic off NAT."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Create ECR/CloudWatch/Secrets interface endpoints to reduce NAT cost (each ~$7/mo). Enable in prod."
  type        = bool
  default     = false
}

variable "interface_endpoint_services" {
  description = "Short service names for interface endpoints to create when enable_interface_endpoints is true."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "logs", "secretsmanager", "ssm"]
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "snow-resorts"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

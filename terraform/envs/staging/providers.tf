provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "snow-resorts"
      Environment = "staging"
      ManagedBy   = "terraform"
    }
  }
}

# Remote state: S3 backend + DynamoDB lock.
#
# Backend config can't use variables, so the bucket/table/region are supplied
# at init time via -backend-config (see README). For local validation use:
#   terraform init -backend=false
#
# Example:
#   terraform init \
#     -backend-config="bucket=snow-resorts-tfstate" \
#     -backend-config="key=prod/terraform.tfstate" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=snow-resorts-tflock" \
#     -backend-config="encrypt=true"
terraform {
  backend "s3" {
    key = "prod/terraform.tfstate"
  }
}

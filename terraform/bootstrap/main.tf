# Creates the S3 bucket that holds the state of every environment.
# Run it once per AWS account. Its own state stays local, since the bucket doesn't exist yet.
terraform {
  required_version = ">= 1.11, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

variable "region" {
  description = "AWS region of the state bucket."
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile for local runs. Leave it null to use the default credential chain."
  type        = string
  default     = null
}

variable "state_bucket_name" {
  description = "Name of the state bucket. S3 bucket names are global, so it must be unique."
  type        = string
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# Versioning makes it possible to recover a previous state.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket_name" {
  description = "Value for -backend-config=\"bucket=...\" in terraform init."
  value       = aws_s3_bucket.state.id
}

# Creates the S3 bucket that holds the state of every environment, and the
# account-level role API Gateway uses for access logs.
# Run it once per AWS account, in the environments' region. Its own state stays
# local, since the bucket doesn't exist yet.
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
  #checkov:skip=CKV_AWS_18:Server access logs add storage cost. CloudTrail data events are the production option.
  #checkov:skip=CKV2_AWS_62:Nothing consumes object events.
  #checkov:skip=CKV_AWS_144:Cross-region replication is part of the documented multi-region next step.
  #checkov:skip=CKV_AWS_145:SSE-S3 encrypts every object. A customer managed key adds cost without a key-access requirement.
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

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  # Every apply writes a new version, so old ones are kept for a while to
  # recover from a bad apply, then removed.
  rule {
    id     = "expire_noncurrent_versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort_incomplete_multipart_uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # A lifecycle rule for noncurrent versions needs versioning to be enabled first.
  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# State can hold sensitive values, so it must never travel over plain HTTP.
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  # Applying a bucket policy while the public access block is still being
  # created can fail, so wait for it.
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# API Gateway writes access logs through a single role per account and region,
# so it lives here rather than in each environment, where they would overwrite it.
resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "api-gateway-cloudwatch-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn

  depends_on = [aws_iam_role_policy_attachment.api_gateway_cloudwatch]
}

output "state_bucket_name" {
  description = "Value for -backend-config=\"bucket=...\" in terraform init."
  value       = aws_s3_bucket.state.id
}

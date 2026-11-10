# Random suffix, because S3 bucket names are global.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "images" {
  #checkov:skip=CKV_AWS_18:Server access logs add storage cost. CloudTrail data events are the production option.
  #checkov:skip=CKV2_AWS_62:Nothing consumes object events.
  #checkov:skip=CKV_AWS_144:Cross-region replication is part of the documented multi-region next step.
  #checkov:skip=CKV_AWS_145:SSE-S3 encrypts every object. A customer managed key adds per-request cost without a key-access requirement.
  bucket        = "${var.name_prefix}-images-${random_id.bucket_suffix.hex}"
  force_destroy = var.force_destroy
}

# Overwritten or deleted images keep their previous version, so they can be
# recovered.
resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "transition_to_standard_ia"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  # Previous versions are only kept long enough to recover from a mistake.
  rule {
    id     = "expire_noncurrent_versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # Parts of an interrupted upload are billed until removed.
  rule {
    id     = "abort_incomplete_multipart_uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # A lifecycle rule for noncurrent versions needs versioning to be enabled first.
  depends_on = [aws_s3_bucket_versioning.images]
}

# Lives here, not in the network module, because it needs the bucket ARN.
# Only the object actions the API uses are allowed, so nothing in the VPC
# can reach other buckets through the endpoint.
resource "aws_vpc_endpoint_policy" "s3" {
  vpc_endpoint_id = var.s3_endpoint_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.images.arn}/*"
      }
    ]
  })
}

# Defense in depth on top of IAM: no plain HTTP, and object data can only be
# read or written through the VPC endpoint. Bucket management and object
# deletion stay reachable from outside, so Terraform can still manage and
# destroy the bucket.
resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.images.arn,
          "${aws_s3_bucket.images.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid       = "DenyObjectDataOutsideVpce"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.images.arn}/*"
        Condition = {
          StringNotEquals = { "aws:sourceVpce" = var.s3_endpoint_id }
        }
      }
    ]
  })

  # Applying a bucket policy while the public access block is still being
  # created can fail, so wait for it.
  depends_on = [aws_s3_bucket_public_access_block.images]
}

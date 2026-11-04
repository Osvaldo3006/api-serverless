data "aws_caller_identity" "current" {}

locals {
  lambda_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  basic_execution_policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "s3" {
  name        = "${var.name_prefix}-s3"
  description = "Policy for accessing S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Effect = "Allow"
        Resource = [
          var.bucket_arn,
          "${var.bucket_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_policy" "aurora" {
  name        = "${var.name_prefix}-aurora"
  description = "Policy to access aurora instance"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = ["arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:${var.cluster_id}/${var.master_username}"]
      }
    ]
  })
}

resource "aws_iam_policy" "eni" {
  name        = "${var.name_prefix}-eni"
  description = "Policy to access EC2 ENI in VPC"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# The API can read its own credentials, but not the master credentials.
resource "aws_iam_policy" "api_secret" {
  name        = "${var.name_prefix}-api-secret"
  description = "Read the API database user's secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.app_secret_arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_policy" "migrator_secrets" {
  name        = "${var.name_prefix}-migrator-secrets"
  description = "Read the master secret and the API database user's secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.master_secret_arn, var.app_secret_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role" "api" {
  name               = "${var.name_prefix}-api-lambda"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "api" {
  for_each = {
    basic  = local.basic_execution_policy_arn
    s3     = aws_iam_policy.s3.arn
    aurora = aws_iam_policy.aurora.arn
    eni    = aws_iam_policy.eni.arn
    secret = aws_iam_policy.api_secret.arn
  }

  role       = aws_iam_role.api.name
  policy_arn = each.value
}

resource "aws_iam_role" "migrator" {
  name               = "${var.name_prefix}-migrator-lambda"
  assume_role_policy = local.lambda_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "migrator" {
  for_each = {
    basic   = local.basic_execution_policy_arn
    eni     = aws_iam_policy.eni.arn
    secrets = aws_iam_policy.migrator_secrets.arn
  }

  role       = aws_iam_role.migrator.name
  policy_arn = each.value
}

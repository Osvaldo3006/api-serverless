# Creates the account-level resources the environments need: the S3 bucket that
# holds their state, the bucket that keeps deployed Lambda packages for
# rollback, the role API Gateway uses for access logs, and the GitHub OIDC
# provider with a read-only plan role and a deploy role.
#
# Each environment has its own AWS account: run this once in the dev account
# with environment = "dev" and once in the prod account with
# environment = "prod", in the environment's region. Its own state stays local,
# since the bucket doesn't exist yet. The account is the boundary between
# environments: the roles' permissions are account-wide (PowerUserAccess,
# ReadOnlyAccess, the rds!cluster-* master secrets), so the dev roles can't
# reach prod only because prod is in another account.
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

  # Guards against running with a profile for the other environment's account.
  allowed_account_ids = [var.aws_account_id]
}

variable "region" {
  description = "AWS region of the state bucket."
  type        = string
}

variable "aws_account_id" {
  description = "ID of the AWS account of this environment. Terraform stops before making any change if the credentials belong to another account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
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

variable "artifacts_bucket_name" {
  description = "Name of the bucket that keeps the deployed Lambda packages for rollback. S3 bucket names are global, so it must be unique."
  type        = string
}

variable "project" {
  description = "Project name. Must match the environments' project variable, since deploy roles can only manage IAM resources named <project>-<environment>-*."
  type        = string
  default     = "serverless-api"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy roles, as owner/repo."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in the form owner/repo."
  }
}

variable "environment" {
  description = "The one environment deployed to this account: \"dev\" or \"prod\"."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

data "aws_caller_identity" "current" {}

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

# Keeps the Lambda package of each deploy, so the deploy workflow can roll back
# to an earlier one. Each environment writes a single key, <environment>/function.zip,
# and versioning keeps the earlier packages as noncurrent versions.
resource "aws_s3_bucket" "artifacts" {
  #checkov:skip=CKV_AWS_18:Server access logs add storage cost. CloudTrail data events are the production option.
  #checkov:skip=CKV2_AWS_62:Nothing consumes object events.
  #checkov:skip=CKV_AWS_144:Cross-region replication is part of the documented multi-region next step.
  #checkov:skip=CKV_AWS_145:SSE-S3 encrypts every object. A customer managed key adds cost without a key-access requirement.
  bucket = var.artifacts_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  # The current package never expires. The two most recent earlier packages
  # are always kept, whatever their age, and older ones are removed 60 days
  # after being replaced.
  rule {
    id     = "keep_rollback_versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = 60
      newer_noncurrent_versions = 2
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

  depends_on = [aws_s3_bucket_versioning.artifacts]
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.artifacts]
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

# GitHub Actions exchanges its OIDC token for temporary credentials, so no AWS
# keys are stored in GitHub. AWS validates GitHub's certificate itself, so no
# thumbprint is pinned.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # GitHub's default sub claim names the repository and environment but not
  # the workflow, so any workflow on main could use the environment. The
  # repository's OIDC sub is customized to also include job_workflow_ref (see
  # the header of deploy.yml), and the roles require deploy.yml from main.
  # Until that is done, the default sub never matches and every run is denied.
  github_workflow_ref = "job_workflow_ref:${var.github_repository}/.github/workflows/deploy.yml@refs/heads/main"
}

# Caps what any role a deploy role creates can do, whatever policies it holds,
# so a deploy role can't escalate by writing a broad policy for a Lambda role.
# It allows only what the Lambdas need. The policies in the iam module still
# grant the least privilege; this is the ceiling. The name is outside the
# <project>-<environment>- prefix, so deploy roles can't change it. The
# environments build its ARN from this name.
resource "aws_iam_policy" "lambda_boundary" {
  name        = "lambda-boundary-${var.environment}"
  description = "Permissions boundary for the ${var.environment} Lambda roles"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteOwnLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/lambda/${var.project}-${var.environment}-*:*"
      },
      {
        # Lambda manages the ENIs of a function in a VPC. Their IDs aren't
        # known ahead of time, so they are scoped to this account and region.
        Sid    = "ManageVpcNetworkInterfaces"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ]
        Resource = "arn:aws:ec2:${var.region}:${local.account_id}:*"
      },
      {
        # Describe actions don't support resource-level permissions.
        Sid    = "DescribeVpcNetworkInterfaces"
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets"
        ]
        Resource = "*"
      },
      {
        Sid    = "UseImagesBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${var.project}-${var.environment}-images-*/*"
      },
      {
        # The app user's secret has the environment prefix. Aurora names the
        # master secret rds!cluster-<id>, so it can't be scoped further.
        Sid    = "ReadDatabaseSecrets"
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:${var.project}-${var.environment}-db-app-*",
          "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:rds!cluster-*"
        ]
      },
      {
        Sid      = "DecryptSecretsThroughSecretsManager"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = "arn:aws:kms:${var.region}:${local.account_id}:key/*"
        Condition = {
          StringEquals = { "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com" }
        }
      }
    ]
  })
}

# Each role trusts only deploy.yml from main, in jobs that run in its own GitHub
# environment of this repository, so a dev job can't assume the prod role.
resource "aws_iam_role" "github_deploy" {
  name = "github-deploy-${var.environment}"

  # Matches the deploy job's 90-minute timeout, so the credentials can't expire
  # in the middle of an apply and leave the state locked.
  max_session_duration = 5400

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:${var.environment}:${local.github_workflow_ref}"
          }
        }
      }
    ]
  })
}

# PowerUserAccess covers every service the environments use except IAM. It is
# account-wide: writing least privilege per service can't be tested without an
# account, and one account per environment is what keeps the blast radius small.
resource "aws_iam_role_policy_attachment" "github_deploy_power_user" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# IAM access is limited to the roles and policies of the role's own environment,
# which the iam module names <project>-<environment>-*. Every role it creates or
# changes must carry the environment's permissions boundary, it can attach only
# the environment's own policies and the AWS managed VPC access policy, and it
# can pass those roles only to Lambda. Inline role policies aren't allowed,
# since the iam module doesn't use them.
resource "aws_iam_role_policy" "github_deploy_iam" {
  name = "environment-iam"
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateAndChangeBoundedRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:PutRolePermissionsBoundary",
          "iam:DetachRolePolicy"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.project}-${var.environment}-*"
        Condition = {
          StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.lambda_boundary.arn }
        }
      },
      {
        Sid      = "AttachAllowedPoliciesToBoundedRoles"
        Effect   = "Allow"
        Action   = "iam:AttachRolePolicy"
        Resource = "arn:aws:iam::${local.account_id}:role/${var.project}-${var.environment}-*"
        Condition = {
          StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.lambda_boundary.arn }
          ArnLike = {
            "iam:PolicyARN" = [
              "arn:aws:iam::${local.account_id}:policy/${var.project}-${var.environment}-*",
              "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
            ]
          }
        }
      },
      {
        # None of these can widen what a role is allowed to do.
        Sid    = "ManageEnvironmentRoles"
        Effect = "Allow"
        Action = [
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.project}-${var.environment}-*"
      },
      {
        Sid    = "ManageEnvironmentPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:TagPolicy",
          "iam:UntagPolicy",
          "iam:ListPolicyTags"
        ]
        Resource = "arn:aws:iam::${local.account_id}:policy/${var.project}-${var.environment}-*"
      },
      {
        Sid      = "PassEnvironmentRolesToLambda"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${local.account_id}:role/${var.project}-${var.environment}-*"
        Condition = {
          StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" }
        }
      }
    ]
  })
}

# Both buckets rely on their earlier versions: the rollback packages are
# versions of one key, and a bad state is recovered from an earlier version.
# Whoever can delete versions or change a bucket's versioning, lifecycle or
# policy can erase that history, so the deploy role is denied it. PowerUserAccess
# grants no IAM and the policy above covers only <project>-<environment>-*
# roles, so the role can't lift these denies. The buckets' configuration is
# changed by applying bootstrap with an administrator's credentials.
resource "aws_iam_role_policy" "github_deploy_protect_buckets" {
  name = "protect-buckets"
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # The workflow only uploads and copies packages.
        Sid    = "KeepRollbackHistory"
        Effect = "Deny"
        Action = [
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:PutBucketVersioning",
          "s3:PutLifecycleConfiguration",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:DeleteBucket"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        # The role still overwrites the current state, since that is how
        # Terraform saves it. The earlier versions stay, so a bad state can be
        # restored by hand while the lifecycle rule keeps them.
        Sid    = "KeepStateHistory"
        Effect = "Deny"
        Action = [
          "s3:DeleteObjectVersion",
          "s3:PutBucketVersioning",
          "s3:PutLifecycleConfiguration",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:DeleteBucket"
        ]
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*"
        ]
      },
      {
        # Deleting the state without a version ID hides it behind a delete
        # marker. Terraform deletes only the lock file next to it, to release
        # the lock. The key must match the backend key in
        # terraform/environments/<env>.
        Sid      = "KeepState"
        Effect   = "Deny"
        Action   = "s3:DeleteObject"
        Resource = "${aws_s3_bucket.state.arn}/${var.environment}/terraform.tfstate"
      }
    ]
  })
}

# The deploy workflow plans with this role before anyone approves the apply, so
# it can't change anything. Each role trusts only its own <environment>-plan
# GitHub environment, which needs no approval.
resource "aws_iam_role" "github_plan" {
  name = "github-plan-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRoleWithWebIdentity"
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:${var.environment}-plan:${local.github_workflow_ref}"
          }
        }
      }
    ]
  })
}

# Reads every resource Terraform refreshes, the state and the rollback packages.
# It doesn't include secretsmanager:GetSecretValue.
resource "aws_iam_role_policy_attachment" "github_plan_read_only" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "github_plan" {
  name = "plan"
  role = aws_iam_role.github_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Planning takes the state lock, a separate object next to the state.
        # The key must match the backend key in terraform/environments/<env>.
        Sid    = "TakeStateLock"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.state.arn}/${var.environment}/terraform.tfstate.tflock"
      },
      {
        # ReadOnlyAccess would let it read the images users upload, which
        # Terraform never needs.
        Sid      = "DenyUserImages"
        Effect   = "Deny"
        Action   = "s3:GetObject*"
        Resource = "arn:aws:s3:::${var.project}-${var.environment}-images-*/*"
      }
    ]
  })
}

output "state_bucket_name" {
  description = "Value for -backend-config=\"bucket=...\" in terraform init."
  value       = aws_s3_bucket.state.id
}

output "artifacts_bucket_name" {
  description = "Value for the ARTIFACTS_BUCKET variable of each <environment>-plan GitHub environment."
  value       = aws_s3_bucket.artifacts.id
}

# Not credentials, but they reveal the account ID. Store them as GitHub
# environment variables and keep them out of logs.
output "github_deploy_role_arn" {
  description = "Value for the AWS_ROLE_ARN variable of the <environment> GitHub environment."
  value       = aws_iam_role.github_deploy.arn
}

output "github_plan_role_arn" {
  description = "Value for the AWS_PLAN_ROLE_ARN variable of the <environment>-plan GitHub environment."
  value       = aws_iam_role.github_plan.arn
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  # Guards local runs against a profile for the wrong account. In CI, each
  # role's trust policy already keeps a job in its own environment's account.
  allowed_account_ids = [var.aws_account_id]

  # Applied to every resource that supports tags, for cost allocation and filtering.
  default_tags {
    tags = {
      Project     = var.project
      Environment = local.environment
    }
  }
}

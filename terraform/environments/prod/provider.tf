provider "aws" {
  region  = var.region
  profile = var.aws_profile

  # Applied to every resource that supports tags, for cost allocation and filtering.
  default_tags {
    tags = {
      Project     = var.project
      Environment = local.environment
    }
  }
}

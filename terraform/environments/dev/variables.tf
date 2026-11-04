variable "project" {
  description = "Project name, used as the prefix of every resource name."
  type        = string
  default     = "serverless-api"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "Use only lowercase letters, digits and hyphens: S3 and RDS reject anything else."
  }
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile for local runs. Leave it null to use the default credential chain, as CI does."
  type        = string
  default     = null
}

variable "cidr_block" {
  description = "CIDR block of the VPC."
  type        = string
}

variable "private_subnets" {
  description = "Number of private subnets. Aurora needs at least two availability zones."
  type        = number
}

variable "database_name" {
  description = "Name of the database to create. Letters, digits and underscores only."
  type        = string
  default     = "webapp"
}

variable "aurora_engine_version" {
  description = "Aurora MySQL engine version."
  type        = string
  default     = "8.0.mysql_aurora.3.10.6"
}

variable "app_db_password_version" {
  description = "Increase this number to generate a new password for the API database user."
  type        = number
  default     = 1
}

variable "artifact_location" {
  description = "Path to the deployment .zip, relative to this directory."
  type        = string
  default     = "../../../serverless-api/dist/function.zip"
}

variable "lambda_runtime" {
  description = "Lambda runtime identifier."
  type        = string
  default     = "nodejs24.x"
}

variable "api_stage" {
  description = "Name of the API Gateway stage."
  type        = string
}

variable "domain" {
  description = "Custom domain of the API, such as api-dev.example.com."
  type        = string
}

variable "hosted_zone_name" {
  description = "Route53 hosted zone, such as example.com. Defaults to the value of domain."
  type        = string
  default     = null
}

variable "certificate_domain" {
  description = "Domain of the ACM certificate, such as *.example.com. Defaults to the value of domain."
  type        = string
  default     = null
}

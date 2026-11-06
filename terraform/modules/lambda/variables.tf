variable "name_prefix" {
  description = "Prefix for resource names, such as serverless-api-dev."
  type        = string
}

variable "artifact_location" {
  description = "Path to the deployment .zip, relative to the directory where Terraform runs."
  type        = string
}

variable "runtime" {
  description = "Lambda runtime identifier."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "subnet_ids" {
  description = "IDs of the private subnets."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups attached to the functions."
  type        = list(string)
}

variable "api_role_arn" {
  description = "ARN of the API Lambda role."
  type        = string
}

variable "migrator_role_arn" {
  description = "ARN of the migration Lambda role."
  type        = string
}

variable "bucket_id" {
  description = "Name of the images bucket."
  type        = string
}

variable "db_host" {
  description = "Writer endpoint of the database."
  type        = string
}

variable "db_name" {
  description = "Name of the database."
  type        = string
}

variable "master_secret_arn" {
  description = "ARN of the secret with the master credentials."
  type        = string
}

variable "app_secret_arn" {
  description = "ARN of the secret with the API database user's credentials."
  type        = string
}

variable "app_db_password_version" {
  description = "Version of the API database user's password. Changing it re-runs the migration Lambda."
  type        = number
}

variable "api_reserved_concurrency" {
  description = "Maximum concurrent instances of the API function, which caps database connections. The default is a placeholder, not based on measured traffic. AWS requires 100 unreserved executions per account, so accounts with a lower concurrency quota fail to apply: request a quota increase or set -1 (no reservation)."
  type        = number
  default     = 10
}

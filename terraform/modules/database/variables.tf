variable "name_prefix" {
  description = "Prefix for resource names, such as serverless-api-dev."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC."
  type        = string
}

variable "subnet_ids" {
  description = "IDs of the private subnets for the database."
  type        = list(string)
}

variable "lambda_security_group_id" {
  description = "Security group allowed to connect to the database."
  type        = string
}

variable "engine_version" {
  description = "Aurora MySQL engine version."
  type        = string
}

variable "database_name" {
  description = "Name of the database to create."
  type        = string
}

variable "app_db_username" {
  description = "Database user for the API, created by the migration Lambda."
  type        = string
  default     = "webapp_api"
}

variable "app_db_password_version" {
  description = "Increase this number to generate a new password for the API database user."
  type        = number
  default     = 1
}

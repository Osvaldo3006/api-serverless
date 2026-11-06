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

# The data protection defaults are the safe ones, so an environment has to opt
# out on purpose.
variable "deletion_protection" {
  description = "Whether AWS rejects deleting the Aurora cluster."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to delete the Aurora cluster without taking a final snapshot."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated Aurora backups, which is how far back point-in-time recovery can go."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
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

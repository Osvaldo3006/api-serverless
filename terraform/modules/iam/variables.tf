variable "name_prefix" {
  description = "Prefix for resource names, such as serverless-api-dev."
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the images bucket."
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

variable "permissions_boundary_arn" {
  description = "ARN of the permissions boundary created in terraform/bootstrap. The deploy roles can only create roles that carry it."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key that encrypts the secrets."
  type        = string
}

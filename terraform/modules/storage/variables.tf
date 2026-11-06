variable "name_prefix" {
  description = "Prefix for resource names, such as serverless-api-dev."
  type        = string
}

variable "force_destroy" {
  description = "Whether destroying the bucket also deletes every object in it. Off by default, so images aren't lost by accident."
  type        = bool
  default     = false
}

variable "s3_endpoint_id" {
  description = "ID of the S3 gateway endpoint, restricted here to the images bucket."
  type        = string
}

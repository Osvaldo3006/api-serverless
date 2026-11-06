variable "name_prefix" {
  description = "Prefix for resource names, such as serverless-api-dev."
  type        = string
}

variable "s3_endpoint_id" {
  description = "ID of the S3 gateway endpoint, restricted here to the images bucket."
  type        = string
}

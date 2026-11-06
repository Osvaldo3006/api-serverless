variable "name_prefix" {
  description = "Prefix for resource names, such as serverless-api-dev."
  type        = string
}

variable "lambda_invoke_arn" {
  description = "Invoke ARN of the API Lambda function."
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the API Lambda function."
  type        = string
}

variable "stage_name" {
  description = "Name of the API Gateway stage."
  type        = string
}

variable "binary_media_types" {
  description = "Content types that API Gateway must pass to Lambda intact, as base64. Without them, uploaded images get corrupted."
  type        = list(string)
  default     = ["multipart/form-data", "image/jpeg", "image/png"]
}

variable "throttling_rate_limit" {
  description = "Steady-state requests per second allowed on the stage. The default is a placeholder, not based on measured traffic."
  type        = number
  default     = 10
}

variable "throttling_burst_limit" {
  description = "Maximum concurrent burst of requests allowed on the stage. The default is a placeholder, not based on measured traffic."
  type        = number
  default     = 20
}

variable "domain" {
  description = "Custom domain of the API, such as api.example.com."
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

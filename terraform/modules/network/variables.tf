variable "name_prefix" {
  description = "Prefix for resource names, such as serverless-api-dev."
  type        = string
}

variable "region" {
  description = "AWS region, used to build the VPC endpoint service names."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block of the VPC."
  type        = string
}

variable "private_subnets" {
  description = "Number of private subnets. Aurora needs at least two availability zones."
  type        = number
}

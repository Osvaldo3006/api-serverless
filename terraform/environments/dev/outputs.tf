output "api_url" {
  description = "Public URL of the API, through the custom domain."
  value       = "https://${module.api_gateway.domain}"
}

output "stage_invoke_url" {
  description = "Default URL of the API Gateway stage, useful before DNS propagates."
  value       = module.api_gateway.stage_invoke_url
}

output "api_function_name" {
  description = "Name of the API Lambda function. Its logs are in /aws/lambda/<name>."
  value       = module.lambda.api_function_name
}

output "migrator_function_name" {
  description = "Name of the migration Lambda function, to re-run migrations by hand."
  value       = module.lambda.migrator_function_name
}

output "images_bucket" {
  description = "Name of the images bucket."
  value       = module.storage.bucket_id
}

output "database_endpoint" {
  description = "Writer endpoint of the Aurora cluster. Only reachable from inside the VPC."
  value       = module.database.endpoint
}

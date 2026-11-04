output "stage_invoke_url" {
  description = "Default URL of the API Gateway stage."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "domain" {
  description = "Custom domain of the API."
  value       = aws_api_gateway_domain_name.this.domain_name
}

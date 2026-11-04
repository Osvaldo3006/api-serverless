output "api_function_name" {
  description = "Name of the API Lambda function."
  value       = aws_lambda_function.api.function_name
}

output "api_invoke_arn" {
  description = "Invoke ARN of the API Lambda function."
  value       = aws_lambda_function.api.invoke_arn
}

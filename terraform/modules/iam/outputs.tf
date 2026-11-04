output "api_role_arn" {
  description = "ARN of the API Lambda role."
  value       = aws_iam_role.api.arn
}

output "migrator_role_arn" {
  description = "ARN of the migration Lambda role."
  value       = aws_iam_role.migrator.arn
}

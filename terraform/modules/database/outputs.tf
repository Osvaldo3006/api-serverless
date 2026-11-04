output "cluster_id" {
  description = "ID of the Aurora cluster."
  value       = aws_rds_cluster.aurora.id
}

output "endpoint" {
  description = "Writer endpoint of the Aurora cluster."
  value       = aws_rds_cluster.aurora.endpoint
}

output "database_name" {
  description = "Name of the database."
  value       = aws_rds_cluster.aurora.database_name
}

output "master_username" {
  description = "Master username of the cluster."
  value       = aws_rds_cluster.aurora.master_username
}

output "master_secret_arn" {
  description = "ARN of the secret with the master credentials. Only the migration Lambda reads it."
  value       = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
}

output "app_secret_arn" {
  description = "ARN of the secret with the API database user's credentials."
  value       = aws_secretsmanager_secret.app_db.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key that encrypts both secrets."
  value       = aws_kms_key.aurora.arn
}

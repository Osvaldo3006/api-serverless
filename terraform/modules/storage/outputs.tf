output "bucket_id" {
  description = "Name of the images bucket."
  value       = aws_s3_bucket.images.id
}

output "bucket_arn" {
  description = "ARN of the images bucket."
  value       = aws_s3_bucket.images.arn
}

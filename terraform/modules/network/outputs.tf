output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "lambda_security_group_id" {
  description = "ID of the security group attached to the Lambda functions."
  value       = aws_security_group.lambda.id
}

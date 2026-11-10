data "aws_availability_zones" "all" {
  state = "available"
}

resource "aws_vpc" "main" {
  #checkov:skip=CKV2_AWS_11:VPC Flow Logs are a documented next step for production.
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# Every VPC comes with a default security group that allows all traffic between
# its members and all egress. Nothing here uses it, and managing it with no
# rules removes them, so a resource created without a security group gets no
# network access by accident.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "private" {
  count             = var.private_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.cidr_block, 4, count.index + 1)
  availability_zone = element(data.aws_availability_zones.all.names, count.index % length(data.aws_availability_zones.all.names))

  tags = {
    Name = "${var.name_prefix}-private-${count.index + 1}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-private"
  }
}

resource "aws_route_table_association" "private" {
  count          = var.private_subnets
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Lives here, not in the lambda module, because the endpoint and database
# security groups reference it. This keeps the module graph free of cycles.
# Egress is managed with standalone rules: Terraform removes the default
# allow-all rule on creation, and the rule to the database lives in the
# database module, which owns that security group.
resource "aws_security_group" "lambda" {
  #checkov:skip=CKV2_AWS_5:False positive. It is attached to both Lambda functions, which receive it from the lambda module's input.
  name        = "${var.name_prefix}-lambda-sg"
  description = "lambda security group to allow inbound/outbound from the VPC"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-lambda-sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_endpoints" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "HTTPS to the interface endpoints"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.endpoint.id
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_s3" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to S3 through the gateway endpoint"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
}

resource "aws_security_group" "endpoint" {
  name        = "${var.name_prefix}-endpoint-sg"
  description = "Interface Endpoint security group to allow inbound/outbound from the VPC"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-endpoint-sg"
  }
}

# No egress rules: the endpoints only answer connections they receive, and
# security groups are stateful.
resource "aws_vpc_security_group_ingress_rule" "endpoint_from_lambda" {
  security_group_id            = aws_security_group.endpoint.id
  description                  = "HTTPS from the Lambda functions"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.lambda.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.main.id
  service_name    = "com.amazonaws.${var.region}.s3"
  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name = "${var.name_prefix}-s3-gateway"
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.endpoint.id]
  subnet_ids          = aws_subnet.private[*].id
  private_dns_enabled = true

  tags = {
    Name = "${var.name_prefix}-secrets-endpoint"
  }
}

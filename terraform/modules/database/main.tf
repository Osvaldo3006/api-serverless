resource "aws_security_group" "database" {
  name        = "${var.name_prefix}-database-sg"
  description = "Database security group to allow inbound/outbound from the VPC"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.lambda_security_group_id]
  }

  tags = {
    Name = "${var.name_prefix}-database-sg"
  }
}

resource "aws_db_subnet_group" "private" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.subnet_ids
}

resource "aws_kms_key" "aurora" {
  description = "${var.name_prefix} Aurora secrets"
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier            = "${var.name_prefix}-aurora"
  engine                        = "aurora-mysql"
  engine_mode                   = "provisioned"
  engine_version                = var.engine_version
  database_name                 = var.database_name
  db_subnet_group_name          = aws_db_subnet_group.private.name
  vpc_security_group_ids        = [aws_security_group.database.id]
  master_username               = "admin"
  manage_master_user_password   = true
  storage_encrypted             = true
  master_user_secret_kms_key_id = aws_kms_key.aurora.key_id
  skip_final_snapshot           = true

  serverlessv2_scaling_configuration {
    max_capacity = 1.0
    min_capacity = 0.5
  }
}

resource "aws_rds_cluster_instance" "aurora" {
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
}

# Credentials of the API's database user. The migration Lambda creates this user
# with data-only privileges, so the API never needs the master credentials.
# Ephemeral and write-only values keep the password out of the Terraform state.
ephemeral "random_password" "app_db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "app_db" {
  name_prefix = "${var.name_prefix}-db-app-"
  description = "Credentials of the API database user"
  kms_key_id  = aws_kms_key.aurora.arn
}

resource "aws_secretsmanager_secret_version" "app_db" {
  secret_id = aws_secretsmanager_secret.app_db.id
  secret_string_wo = jsonencode({
    username = var.app_db_username
    password = ephemeral.random_password.app_db.result
  })
  secret_string_wo_version = var.app_db_password_version
}

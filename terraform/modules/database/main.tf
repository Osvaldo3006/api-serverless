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

# Belongs to the Lambda security group, but lives here because the network
# module can't reference the database security group without a cycle.
resource "aws_vpc_security_group_egress_rule" "lambda_to_database" {
  security_group_id            = var.lambda_security_group_id
  description                  = "MySQL to Aurora"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.database.id
}

resource "aws_db_subnet_group" "private" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.subnet_ids
}

resource "aws_kms_key" "aurora" {
  description         = "${var.name_prefix} Aurora secrets"
  enable_key_rotation = true
}

resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.name_prefix}-aurora-mysql8"
  family      = "aurora-mysql8.0"
  description = "${var.name_prefix} Aurora MySQL cluster parameters"

  # Reject connections that don't use TLS.
  parameter {
    name  = "require_secure_transport"
    value = "ON"
  }
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier              = "${var.name_prefix}-aurora"
  engine                          = "aurora-mysql"
  engine_mode                     = "provisioned"
  engine_version                  = var.engine_version
  database_name                   = var.database_name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  db_subnet_group_name            = aws_db_subnet_group.private.name
  vpc_security_group_ids          = [aws_security_group.database.id]
  master_username                 = "admin"
  manage_master_user_password     = true
  storage_encrypted               = true
  master_user_secret_kms_key_id   = aws_kms_key.aurora.key_id
  deletion_protection             = var.deletion_protection
  backup_retention_period         = var.backup_retention_period
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : "${var.name_prefix}-aurora-final"
  copy_tags_to_snapshot           = true

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

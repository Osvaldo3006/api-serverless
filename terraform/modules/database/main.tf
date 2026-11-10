resource "aws_security_group" "database" {
  name        = "${var.name_prefix}-database-sg"
  description = "Database security group to allow inbound/outbound from the VPC"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from the Lambda functions"
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

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

resource "aws_kms_key" "aurora" {
  description         = "${var.name_prefix} Aurora storage and secrets"
  enable_key_rotation = true

  # Same access as the default key policy, written out so it is reviewable:
  # the account delegates to IAM, so only principals whose IAM policies allow
  # it can use the key. The Lambda roles get kms:Decrypt that way. Naming
  # them here instead would create a cycle with the iam module.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIamPolicies"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
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
  #checkov:skip=CKV2_AWS_8:Automated backups (backup_retention_period) cover recovery. AWS Backup adds cost without a cross-account or cross-region need yet.
  #checkov:skip=CKV_AWS_139:Set per environment through var.deletion_protection. prod enables it; dev disables it so it stays destroyable.
  #checkov:skip=CKV_AWS_162:By design. The API uses a dedicated data-only user whose password lives in Secrets Manager.
  #checkov:skip=CKV_AWS_324:Exporting database logs to CloudWatch adds ingestion cost. Left out until there is a need.
  #checkov:skip=CKV_AWS_325:Audit logging adds ingestion cost. Left out until there is a need.
  #checkov:skip=CKV_AWS_326:Backtrack is billed per change record. Point-in-time restore from automated backups covers recovery.
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
  kms_key_id                      = aws_kms_key.aurora.arn
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
  #checkov:skip=CKV_AWS_118:Enhanced Monitoring adds cost. Standard CloudWatch metrics are enough for this workload.
  #checkov:skip=CKV_AWS_353:Performance Insights adds cost. Left out until there is a performance problem to investigate.
  cluster_identifier         = aws_rds_cluster.aurora.id
  instance_class             = "db.serverless"
  engine                     = aws_rds_cluster.aurora.engine
  engine_version             = aws_rds_cluster.aurora.engine_version
  auto_minor_version_upgrade = true
}

# Credentials of the API's database user. The migration Lambda creates this user
# with data-only privileges, so the API never needs the master credentials.
# Ephemeral and write-only values keep the password out of the Terraform state.
ephemeral "random_password" "app_db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "app_db" {
  #checkov:skip=CKV2_AWS_57:Automatic rotation is a documented next step. It is rotated by increasing app_db_password_version.
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

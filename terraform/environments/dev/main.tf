locals {
  environment = "dev"
  name_prefix = "${var.project}-${local.environment}"

  # dev stays destroyable: a destroy removes the database and the images.
  deletion_protection     = false
  skip_final_snapshot     = true
  backup_retention_period = 1
  force_destroy           = true

  # Short retention keeps cost low. dev logs aren't kept for auditing.
  log_retention_days = 7
}

module "network" {
  source = "../../modules/network"

  name_prefix     = local.name_prefix
  region          = var.region
  cidr_block      = var.cidr_block
  private_subnets = var.private_subnets
}

module "database" {
  source = "../../modules/database"

  name_prefix              = local.name_prefix
  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.private_subnet_ids
  lambda_security_group_id = module.network.lambda_security_group_id
  engine_version           = var.aurora_engine_version
  database_name            = var.database_name
  app_db_password_version  = var.app_db_password_version
  deletion_protection      = local.deletion_protection
  skip_final_snapshot      = local.skip_final_snapshot
  backup_retention_period  = local.backup_retention_period
}

module "storage" {
  source = "../../modules/storage"

  name_prefix    = local.name_prefix
  s3_endpoint_id = module.network.s3_endpoint_id
  force_destroy  = local.force_destroy
}

module "iam" {
  source = "../../modules/iam"

  name_prefix       = local.name_prefix
  bucket_arn        = module.storage.bucket_arn
  master_secret_arn = module.database.master_secret_arn
  app_secret_arn    = module.database.app_secret_arn
  kms_key_arn       = module.database.kms_key_arn
}

module "lambda" {
  source = "../../modules/lambda"

  name_prefix             = local.name_prefix
  artifact_location       = var.artifact_location
  runtime                 = var.lambda_runtime
  region                  = var.region
  subnet_ids              = module.network.private_subnet_ids
  security_group_ids      = [module.network.lambda_security_group_id]
  api_role_arn            = module.iam.api_role_arn
  migrator_role_arn       = module.iam.migrator_role_arn
  bucket_id               = module.storage.bucket_id
  db_host                 = module.database.endpoint
  db_name                 = module.database.database_name
  master_secret_arn       = module.database.master_secret_arn
  app_secret_arn          = module.database.app_secret_arn
  app_db_password_version = var.app_db_password_version
  log_retention_days      = local.log_retention_days

  # The migration Lambda runs during apply, so it needs the database instance,
  # the Secrets Manager endpoint and the IAM policy attachments to exist first.
  depends_on = [module.network, module.database, module.iam]
}

module "api_gateway" {
  source = "../../modules/api-gateway"

  name_prefix          = local.name_prefix
  lambda_invoke_arn    = module.lambda.api_invoke_arn
  lambda_function_name = module.lambda.api_function_name
  stage_name           = var.api_stage
  domain               = var.domain
  hosted_zone_name     = var.hosted_zone_name
  certificate_domain   = var.certificate_domain
  log_retention_days   = local.log_retention_days
}

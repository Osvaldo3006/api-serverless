locals {
  artifact_hash = filebase64sha256(var.artifact_location)

  common_environment = {
    ENVIRONMENT = "lambda"
    REGION      = var.region
    HOST        = var.db_host
    DATABASE    = var.db_name
    DB_TLS      = "true"
  }
}

resource "aws_lambda_function" "api" {
  function_name    = "${var.name_prefix}-api"
  filename         = var.artifact_location
  source_code_hash = local.artifact_hash
  role             = var.api_role_arn
  handler          = "index.handler"
  runtime          = var.runtime
  timeout          = 30

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  environment {
    variables = merge(local.common_environment, {
      S3_BUCKET = var.bucket_id
      SECRET_ID = var.app_secret_arn
    })
  }
}

# Same artifact, different entry point and role: only this function can use the master credentials.
resource "aws_lambda_function" "migrator" {
  function_name    = "${var.name_prefix}-migrator"
  filename         = var.artifact_location
  source_code_hash = local.artifact_hash
  role             = var.migrator_role_arn
  handler          = "migrate.handler"
  runtime          = var.runtime
  timeout          = 120

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  environment {
    variables = merge(local.common_environment, {
      SECRET_ID     = var.master_secret_arn
      APP_SECRET_ID = var.app_secret_arn
    })
  }
}

# Applies pending migrations whenever the code or the API user's secret changes.
resource "aws_lambda_invocation" "migrate" {
  function_name = aws_lambda_function.migrator.function_name
  input         = jsonencode({})

  triggers = {
    artifact_hash   = local.artifact_hash
    db_password_rev = var.app_db_password_version
  }
}

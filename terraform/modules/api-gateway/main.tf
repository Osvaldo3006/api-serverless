resource "aws_api_gateway_rest_api" "this" {
  #checkov:skip=CKV_AWS_237:Updated in place, never replaced. The deployment, which is replaced on every change, already uses create_before_destroy.
  name               = var.name_prefix
  description        = "Inventory Management API"
  binary_media_types = var.binary_media_types

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Express does the routing (and answers 404 and 405), so API Gateway only
# forwards everything to Lambda: the root path, and any other path through {proxy+}.
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "root" {
  #checkov:skip=CKV_AWS_59:By design. Express checks HTTP Basic credentials, and some routes are public.
  #checkov:skip=CKV2_AWS_53:By design. Requests are proxied to Express, which validates them.
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_rest_api.this.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "proxy" {
  #checkov:skip=CKV_AWS_59:By design. Express checks HTTP Basic credentials, and some routes are public.
  #checkov:skip=CKV2_AWS_53:By design. Requests are proxied to Express, which validates them.
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_method.root.resource_id
  http_method             = aws_api_gateway_method.root.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_method.proxy.resource_id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  # Any change to the API's configuration must produce a new deployment.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.this.binary_media_types,
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.root.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.root.id,
      aws_api_gateway_integration.root.uri,
      aws_api_gateway_integration.proxy.id,
      aws_api_gateway_integration.proxy.uri,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.root,
    aws_api_gateway_integration.proxy,
  ]
}

resource "aws_cloudwatch_log_group" "access" {
  #checkov:skip=CKV_AWS_158:Logs hold no secrets and are encrypted by CloudWatch. A customer managed key adds cost without a key-access requirement.
  name              = "/aws/apigateway/${var.name_prefix}-access"
  retention_in_days = var.log_retention_days
}

# Writing to CloudWatch needs the account-level role created in terraform/bootstrap.
resource "aws_api_gateway_stage" "this" {
  #checkov:skip=CKV2_AWS_4:Access logs are enabled. Execution logs would go to a log group API Gateway creates itself, with no retention, outside Terraform.
  #checkov:skip=CKV_AWS_73:X-Ray tracing is a documented next step for production.
  #checkov:skip=CKV2_AWS_29:WAF is a documented next step for production. Stage throttling limits request volume meanwhile.
  #checkov:skip=CKV2_AWS_51:Client certificates authenticate API Gateway to HTTP backends. The Lambda proxy integration doesn't use them.
  #checkov:skip=CKV_AWS_120:Responses depend on the caller's credentials, so caching them is unsafe, and the cache is billed hourly.
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name

  # One JSON line per request. Request headers are left out, so the Basic Auth
  # credentials never reach the logs.
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.access.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      ip                 = "$context.identity.sourceIp"
      userAgent          = "$context.identity.userAgent"
      requestTime        = "$context.requestTime"
      httpMethod         = "$context.httpMethod"
      path               = "$context.path"
      protocol           = "$context.protocol"
      status             = "$context.status"
      responseLength     = "$context.responseLength"
      responseLatency    = "$context.responseLatency"
      integrationLatency = "$context.integrationLatency"
      integrationError   = "$context.integrationErrorMessage"
    })
  }
}

# Limits apply to the whole stage, not per client. Requests over the limit get
# a 429 without invoking Lambda, which caps cost and slows Basic Auth guessing.
resource "aws_api_gateway_method_settings" "all" {
  #checkov:skip=CKV_AWS_225:Responses depend on the caller's credentials, so caching them is unsafe, and the cache is billed hourly.
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = var.throttling_rate_limit
    throttling_burst_limit = var.throttling_burst_limit
  }
}

data "aws_acm_certificate" "api" {
  domain   = coalesce(var.certificate_domain, var.domain)
  statuses = ["ISSUED"]
}

resource "aws_api_gateway_domain_name" "this" {
  domain_name              = var.domain
  regional_certificate_arn = data.aws_acm_certificate.api.arn
  security_policy          = "TLS_1_2"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

data "aws_route53_zone" "api" {
  name = coalesce(var.hosted_zone_name, var.domain)
}

resource "aws_route53_record" "api" {
  name    = aws_api_gateway_domain_name.this.domain_name
  type    = "A"
  zone_id = data.aws_route53_zone.api.id

  alias {
    evaluate_target_health = true
    name                   = aws_api_gateway_domain_name.this.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.this.regional_zone_id
  }
}

resource "aws_api_gateway_base_path_mapping" "this" {
  api_id      = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  domain_name = aws_api_gateway_domain_name.this.domain_name
}

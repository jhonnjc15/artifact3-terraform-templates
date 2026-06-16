locals {
  clean_code_prefix = trim(var.code_prefix, "/")
}

data "archive_file" "this" {
  count = try(var.lambda.enabled, false) ? 1 : 0

  type        = "zip"
  source_dir  = var.lambda.source_path
  output_path = "${path.module}/.terraform/lambda_zips/${try(var.lambda.function_name, "function")}.zip"
}

resource "aws_s3_object" "this" {
  count = try(var.lambda.enabled, false) ? 1 : 0

  bucket = var.artifact_bucket
  key    = "${local.clean_code_prefix}/${try(var.lambda.function_name, "function")}/code.zip"
  source = data.archive_file.this[0].output_path
  etag   = filemd5(data.archive_file.this[0].output_path)

  tags = var.tags
}

resource "aws_lambda_function" "this" {
  count = try(var.lambda.enabled, false) ? 1 : 0

  function_name = var.lambda.function_name
  role          = var.lambda_role_arn
  handler       = try(var.lambda.handler, "main.handler")
  runtime       = try(var.lambda.runtime, "python3.11")
  timeout       = try(var.lambda.timeout, 30)
  memory_size   = try(var.lambda.memory_size, 256)
  description   = try(var.lambda.description, null)

  s3_bucket = var.artifact_bucket
  s3_key    = aws_s3_object.this[0].key

  dynamic "environment" {
    for_each = try(var.lambda.environment_variables, null) != null ? [1] : []
    content {
      variables = var.lambda.environment_variables
    }
  }

  tags = var.tags
}

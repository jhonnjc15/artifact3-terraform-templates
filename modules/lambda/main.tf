locals {
  clean_code_prefix = trim(var.code_prefix, "/")
  lambda_source_files = sort([
    for file in try(fileset(var.lambda.source_path, "**"), []) : file
    if !can(regex("(^|/)__pycache__/", file))
    && !endswith(file, ".pyc")
    && !endswith(file, ".pyo")
    && !endswith(file, ".DS_Store")
  ])
  lambda_source_hash = sha256(join("", [
    for file in local.lambda_source_files :
    "${file}:${filesha256("${var.lambda.source_path}/${file}")}"
  ]))
}

data "archive_file" "this" {
  count = try(var.lambda.enabled, false) ? 1 : 0

  type        = "zip"
  source_dir  = var.lambda.source_path
  output_path = "${path.module}/.terraform/lambda_zips/${try(var.lambda.function_name, "function")}.zip"
  excludes = concat(
    [
      "**/__pycache__/**",
      "**/*.pyc",
      "**/*.pyo",
      "**/.DS_Store",
    ],
    try(var.lambda.archive_excludes, [])
  )
}

resource "aws_s3_object" "this" {
  count = try(var.lambda.enabled, false) ? 1 : 0

  bucket = var.artifact_bucket
  key    = "${local.clean_code_prefix}/${try(var.lambda.function_name, "function")}/code.zip"
  source = data.archive_file.this[0].output_path
  # The generated ZIP can contain non-deterministic metadata. Track changes from
  # source file content instead so plans stay stable when source files do not change.
  source_hash = local.lambda_source_hash

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

  source_code_hash = base64sha256(local.lambda_source_hash)

  dynamic "environment" {
    for_each = try(var.lambda.environment_variables, null) != null ? [1] : []
    content {
      variables = var.lambda.environment_variables
    }
  }

  tags = var.tags
}

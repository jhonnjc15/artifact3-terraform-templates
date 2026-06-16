locals {
  sql_content = try(var.athena.sql_path, null) != null ? file(var.athena.sql_path) : null
}

resource "aws_athena_workgroup" "this" {
  count = try(var.athena.enabled, false) ? 1 : 0

  name = try(var.athena.workgroup_name, "primary")

  configuration {
    result_configuration {
      output_location = "s3://${var.output_bucket}/athena-results/"
    }
  }

  tags = var.tags
}

resource "aws_glue_catalog_database" "this" {
  count = try(var.athena.enabled, false) ? 1 : 0

  name        = try(var.athena.database_name, "default")
  description = try(var.athena.description, null)

  tags = var.tags
}

resource "aws_athena_named_query" "this" {
  count = try(var.athena.enabled, false) && local.sql_content != null ? 1 : 0

  name      = try(var.athena.query_name, "ddl-query")
  database  = try(var.athena.database_name, "default")
  query     = local.sql_content
  workgroup = try(var.athena.workgroup_name, "primary")

  depends_on = [
    aws_athena_workgroup.this,
    aws_glue_catalog_database.this,
  ]
}

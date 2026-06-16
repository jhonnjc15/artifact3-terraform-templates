locals {
  clean_scripts_prefix = trim(var.scripts_prefix, "/")

  base_default_arguments = {
    "--TempDir"                           = "s3://${var.temp_bucket}/temporary/"
    "--job-language"                      = "python"
    "--enable-metrics"                    = "true"
    "--enable-glue-datacatalog"           = "true"
    "--enable-continuous-cloudwatch-log"  = "true"
    "--conf"                              = "spark.eventLog.rolling.enabled=true"
  }
}

resource "aws_s3_object" "glue_script" {
  for_each = var.glue_jobs

  bucket = var.artifact_bucket
  key = try(each.value.script_s3_key, "${local.clean_scripts_prefix}/${each.key}/${basename(each.value.script_local_path)}")
  source = each.value.script_local_path
  etag   = filemd5(each.value.script_local_path)

  tags = merge(var.tags, try(each.value.tags, {}))
}

resource "aws_glue_job" "this" {
  for_each = var.glue_jobs

  name              = each.value.job_name
  description       = try(each.value.description, null)
  role_arn          = var.glue_role_arn
  glue_version      = try(each.value.glue_version, "4.0")
  worker_type       = try(each.value.worker_type, "G.1X")
  number_of_workers = try(each.value.number_of_workers, 2)
  timeout           = try(each.value.timeout, 30)
  max_retries       = try(each.value.max_retries, 0)

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_object.glue_script[each.key].bucket}/${aws_s3_object.glue_script[each.key].key}"
    python_version  = try(each.value.python_version, "3")
  }

  default_arguments = merge(
    local.base_default_arguments,
    try(each.value.default_arguments, {})
  )

  execution_property {
    max_concurrent_runs = try(each.value.max_concurrent_runs, 1)
  }

  tags = merge(var.tags, try(each.value.tags, {}))
}

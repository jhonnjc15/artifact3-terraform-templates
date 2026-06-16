output "glue_job_names" {
  description = "Nombres de Glue Jobs creados."
  value       = { for k, v in aws_glue_job.this : k => v.name }
}

output "script_s3_locations" {
  description = "Ubicaciones S3 de los scripts subidos."
  value       = { for k, v in aws_s3_object.glue_script : k => "s3://${v.bucket}/${v.key}" }
}

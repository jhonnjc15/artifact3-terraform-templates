output "function_name" {
  description = "Nombre de la función Lambda creada."
  value       = try(aws_lambda_function.this[0].function_name, null)
}

output "function_arn" {
  description = "ARN de la función Lambda creada."
  value       = try(aws_lambda_function.this[0].arn, null)
}

output "s3_key" {
  description = "Ruta S3 del código subido."
  value       = try(aws_s3_object.this[0].key, null)
}

output "database_name" {
  description = "Nombre de la base de datos Glue creada."
  value       = try(aws_glue_catalog_database.this[0].name, null)
}

output "table_name" {
  description = "Nombre de la tabla Glue creada."
  value       = try(aws_glue_catalog_table.this[0].name, null)
}

output "s3_location" {
  description = "Ubicación S3 de los datos."
  value       = try(aws_glue_catalog_table.this[0].storage_descriptor[0].location, null)
}

output "database_name" {
  description = "Nombre de la base de datos Glue creada."
  value       = try(aws_glue_catalog_database.this[0].name, null)
}

output "workgroup_name" {
  description = "Nombre del workgroup Athena."
  value       = try(aws_athena_workgroup.this[0].name, null)
}

output "named_query_id" {
  description = "ID del named query Athena registrado."
  value       = try(aws_athena_named_query.this[0].id, null)
}

variable "athena" {
  description = "Configuración del query Athena. Objeto con: enabled, sql_path, database_name, workgroup_name."
  type        = any
  default     = {}
}

variable "output_bucket" {
  description = "Bucket S3 donde se almacenarán los resultados de consultas Athena."
  type        = string
}

variable "tags" {
  description = "Tags base para los recursos."
  type        = map(string)
  default     = {}
}

variable "athena" {
  description = "Configuración Athena. database_name, table_name y s3_location pueden venir como override; si no, se extraen del SQL."
  type        = any
  default     = {}
}

variable "tags" {
  description = "Tags base para los recursos."
  type        = map(string)
  default     = {}
}

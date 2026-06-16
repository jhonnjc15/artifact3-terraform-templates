variable "athena" {
  description = "Configuración del query Athena. Objeto con: enabled, sql_path. database_name se extrae automáticamente del SQL."
  type        = any
  default     = {}
}

variable "tags" {
  description = "Tags base para los recursos."
  type        = map(string)
  default     = {}
}

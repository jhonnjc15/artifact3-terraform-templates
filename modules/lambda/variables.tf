variable "artifact_bucket" {
  description = "Bucket S3 donde se sube el código Lambda."
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN del IAM Role que usará la función Lambda."
  type        = string
}

variable "lambda" {
  description = "Configuración de la función Lambda. Objeto con: enabled, function_name, source_path, timeout, memory_size, handler, runtime."
  type        = any
  default     = {}
}

variable "code_prefix" {
  description = "Prefijo S3 donde se alojará el código Lambda."
  type        = string
  default     = "lambda/code"
}

variable "tags" {
  description = "Tags base para los recursos."
  type        = map(string)
  default     = {}
}

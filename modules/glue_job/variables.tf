variable "artifact_bucket" {
  description = "Bucket S3 donde se suben los scripts Python de Glue."
  type        = string
}

variable "temp_bucket" {
  description = "Bucket S3 usado para el TempDir de Glue."
  type        = string
}

variable "glue_role_arn" {
  description = "ARN del IAM Role que usará AWS Glue."
  type        = string
}

variable "scripts_prefix" {
  description = "Prefijo S3 donde se alojarán los scripts Glue."
  type        = string
  default     = "glue/jobs"
}

variable "glue_jobs" {
  description = "Mapa de Glue Jobs a crear. Cada job puede incluir default_arguments genéricos."
  type        = map(any)
  default     = {}
}

variable "tags" {
  description = "Tags base para los recursos."
  type        = map(string)
  default     = {}
}

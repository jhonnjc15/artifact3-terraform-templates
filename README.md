# artifact3-terraform-templates

Repositorio central de templates Terraform para el Artefacto 3.

Esta versión es intencionalmente simple para prueba:

- Solo incluye el módulo `glue_job`.
- No incluye carpeta `examples`.
- No incluye validaciones pre-deploy.
- El módulo crea uno o más AWS Glue Jobs.
- El módulo sube el script Python del job a S3.
- El módulo permite recibir `default_arguments` genéricos por cada job.

## Estructura

```text
artifact3-terraform-templates/
└── modules/
    └── glue_job/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── versions.tf
```

## Idea

El repo consumidor referencia este módulo como source:

```hcl
module "glue_jobs" {
  source = "../artifact3-terraform-templates/modules/glue_job"

  artifact_bucket = var.artifact_bucket
  temp_bucket     = var.temp_bucket
  glue_role_arn   = var.glue_role_arn
  scripts_prefix  = "glue/jobs/dev"
  glue_jobs       = local.enabled_glue_jobs
}
```

Para usarlo desde GitHub Actions, el workflow del repo consumidor hace checkout de ambos repos en carpetas hermanas.

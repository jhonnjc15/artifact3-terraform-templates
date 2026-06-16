# artifact3-terraform-templates

Repositorio central de templates Terraform para el Artefacto 3.

Módulos disponibles:

- `glue_job` — Crea AWS Glue Jobs con scripts subidos a S3.
- `athena` — Crea base de datos Glue, workgroup Athena y registra named queries desde archivos SQL.
- `lambda` — Empaqueta código Lambda desde un directorio, lo sube a S3 y crea la función.

## Estructura

```text
artifact3-terraform-templates/
└── modules/
    ├── glue_job/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── versions.tf
    ├── athena/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── versions.tf
    └── lambda/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── versions.tf
```

## Uso

Cada módulo se referencia desde el `main.tf` del repo consumidor:

```hcl
module "glue_jobs" {
  source = "git::https://github.com/jhonnjc15/artifact3-terraform-templates.git//modules/glue_job?ref=main"
  ...
}

module "athena" {
  source = "git::https://github.com/jhonnjc15/artifact3-terraform-templates.git//modules/athena?ref=main"
  ...
}

module "lambda" {
  source = "git::https://github.com/jhonnjc15/artifact3-terraform-templates.git//modules/lambda?ref=main"
  ...
}
```

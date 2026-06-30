# artifact3-terraform-templates

Repositorio central de templates Terraform para el Artefacto 3.

Guia funcional detallada: [`DOCUMENTO_FUNCIONAL.md`](DOCUMENTO_FUNCIONAL.md).

Módulos disponibles:

- `glue_job` — Crea AWS Glue Jobs con scripts subidos a S3.
- `athena` — Crea tablas Glue/Athena `EXTERNAL_TABLE` desde archivos SQL. La base de datos se gestiona desde el repo consumidor mediante el bloque `databases`.
- `lambda` — Empaqueta código Lambda desde un directorio, lo sube a S3 y crea la función.

## Estructura

```text
artifact3-terraform-templates/
└── modules/
    ├── glue_job/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   ├── versions.tf
    │   └── validations/validate.sh
    ├── athena/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── versions.tf
    └── lambda/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        ├── versions.tf
        └── validations/validate.sh
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

Para consumers productivos se recomienda usar tags versionados en lugar de `ref=main`.

## Validaciones

Las validaciones reutilizables viven en los modulos y se ejecutan desde el workflow del repo consumidor antes de `terraform init`.

| Modulo | Script | Valida |
|---|---|---|
| `glue_job` | `modules/glue_job/validations/validate.sh` | Sintaxis Python, lint critico, `GlueContext`, lectura, escritura y `try/except` |
| `lambda` | `modules/lambda/validations/validate.sh` | `source_path`, `timeout`, `memory_size`, lint/sintaxis y escaneo basico de secretos |

## Notas de diseno

- El modulo `athena` prioriza valores del consumer sobre valores parseados del SQL.
- El modulo `lambda` usa hash deterministico de archivos fuente para evitar cambios por ZIP no deterministico.
- Los modulos no ejecutan validaciones con `local-exec`; esa responsabilidad queda en CI/CD.

# Documento Funcional - Artifact 3 Terraform Templates

## Objetivo

`artifact3-terraform-templates` es la libreria central de modulos Terraform reutilizables. Su objetivo es estandarizar la creacion de recursos de datos y computo para repos consumidores sin duplicar logica Terraform.

## Alcance

Este repo contiene modulos, no despliega recursos por si mismo. Los recursos se crean cuando un repo consumidor referencia estos modulos y entrega valores desde su propio `deploy.json`, variables Terraform y workflow CI/CD.

## Modulos Disponibles

| Modulo | Ruta | Responsabilidad |
|---|---|---|
| Athena | `modules/athena` | Crear Glue table consultable por Athena dentro de una database ya resuelta por el consumer |
| Glue Job | `modules/glue_job` | Subir scripts a S3 y crear AWS Glue Jobs |
| Lambda | `modules/lambda` | Empaquetar codigo, subir ZIP a S3 y crear AWS Lambda |

## Patron De Consumo

Un repo consumidor debe:

1. Declarar sus componentes en `deploy.json`.
2. Filtrar recursos por `enabled` y `enabled_environments` en su `main.tf`.
3. Pasar mapas ya normalizados a los modulos.
4. Ejecutar validaciones pre-deploy desde GitHub Actions.
5. Ejecutar Terraform con backend remoto propio.

Ejemplo de fuente remota:

```hcl
source = "git::https://github.com/jhonnjc15/artifact3-terraform-templates.git//modules/glue_job?ref=<tag>"
```

Para desarrollo local o workflows que clonan templates como carpeta hermana tambien se puede usar:

```hcl
source = "../artifact3-terraform-templates/modules/glue_job"
```

## Modulo Athena

Ruta:

```text
modules/athena
```

### Responsabilidad

Crear una tabla Glue/Athena a partir de un archivo SQL, permitiendo que el repo consumidor sobrescriba valores clave desde `deploy.json`. La Glue Database se crea o referencia fuera del modulo, normalmente desde un bloque `databases` en el repo consumidor.

### Entrada Principal

```hcl
variable "athena" {
  type = any
}
```

Campos esperados o soportados:

| Campo | Funcion |
|---|---|
| `enabled` | Activa o desactiva la creacion |
| `sql_path` | Ruta al SQL base |
| `database_name` | Database final ya resuelta por el consumer |
| `table_name` | Override opcional de tabla |
| `s3_location` | Override opcional de ubicacion S3 |
| `description` | Descripcion de database/table |
| `table_type` | Tipo de tabla, incluido soporte Iceberg basico |
| `parameters` | Parametros adicionales de tabla |
| `merge_existing` | Lee tabla existente para merge aditivo |
| `column_operations.drop` | Elimina columnas del modelo final |
| `column_operations.rename` | Renombra columnas del modelo final |

### Prioridad De Valores

Para database, tabla y ubicacion S3 se aplica esta prioridad:

```text
deploy.json / Terraform input -> SQL
```

Esto permite mantener SQL reutilizable y ajustar nombres fisicos o rutas por ambiente desde el consumer.

### Recursos Creados

| Recurso Terraform | Recurso AWS |
|---|---|
| `aws_glue_catalog_table.this` | Glue table |

### Limitaciones

| Punto | Detalle |
|---|---|
| Parser SQL | Usa regex, por lo que SQL muy complejo puede no parsearse correctamente |
| `merge_existing` | Requiere que la tabla exista si se activa |
| DDL avanzado | No reemplaza un parser SQL completo |

## Modulo Glue Job

Ruta:

```text
modules/glue_job
```

### Responsabilidad

Subir scripts Glue a S3 y crear jobs Glue con configuracion estandar.

### Entradas Principales

| Variable | Funcion |
|---|---|
| `artifact_bucket` | Bucket donde se suben scripts |
| `temp_bucket` | Bucket temporal usado por Glue |
| `glue_role_arn` | Role de ejecucion del Glue Job |
| `scripts_prefix` | Prefijo S3 para scripts |
| `glue_jobs` | Mapa de jobs a crear |
| `tags` | Tags comunes |

### Campos Por Job

| Campo | Funcion |
|---|---|
| `job_name` | Nombre fisico del Glue Job |
| `script_local_path` | Ruta local al script Python |
| `description` | Descripcion opcional |
| `glue_version` | Version Glue, default `4.0` |
| `python_version` | Version Python, default `3` |
| `worker_type` | Tipo worker, default `G.1X` |
| `number_of_workers` | Cantidad workers, default `2` |
| `timeout` | Timeout en minutos, default `30` |
| `max_retries` | Reintentos, default `0` |
| `default_arguments` | Argumentos runtime adicionales |
| `script_s3_key` | Key S3 opcional para el script |
| `tags` | Tags especificos del job |

### Default Arguments Base

El modulo agrega:

```text
--TempDir
--job-language
--enable-metrics
--enable-glue-datacatalog
--enable-continuous-cloudwatch-log
--conf
```

Los `default_arguments` del consumer se mergean encima de estos valores.

### Recursos Creados

| Recurso Terraform | Recurso AWS |
|---|---|
| `aws_s3_object.glue_script` | Script Python en S3 |
| `aws_glue_job.this` | Glue Job |

## Modulo Lambda

Ruta:

```text
modules/lambda
```

### Responsabilidad

Empaquetar codigo Lambda, subir el ZIP a S3 y crear la funcion Lambda.

### Entradas Principales

| Variable | Funcion |
|---|---|
| `artifact_bucket` | Bucket donde se sube el ZIP |
| `lambda_role_arn` | Role de ejecucion Lambda |
| `lambda` | Configuracion de la funcion |
| `code_prefix` | Prefijo S3 para ZIPs |
| `tags` | Tags comunes |

### Campos Por Lambda

| Campo | Funcion |
|---|---|
| `function_name` | Nombre fisico |
| `source_path` | Directorio o archivo fuente |
| `handler` | Handler, default `main.handler` |
| `runtime` | Runtime, default `python3.11` |
| `timeout` | Timeout, default `30` |
| `memory_size` | Memoria, default `256` |
| `description` | Descripcion opcional |
| `environment_variables` | Variables de entorno opcionales |
| `archive_excludes` | Exclusiones adicionales del ZIP |

### Hash Deterministico

El modulo evita depender del hash del ZIP generado, porque el ZIP puede incluir metadata no deterministica. En su lugar calcula un hash de archivos fuente y lo usa como:

| Campo | Uso |
|---|---|
| `source_hash` | Detectar cambios del objeto S3 |
| `source_code_hash` | Detectar cambios de codigo Lambda |

Archivos excluidos por defecto:

```text
__pycache__
*.pyc
*.pyo
.DS_Store
```

## Validaciones Reutilizables

Las validaciones viven dentro de cada modulo, pero se ejecutan desde el workflow del repo consumidor antes de `terraform init`.

### Glue Job

Archivo:

```text
modules/glue_job/validations/validate.sh
```

Valida:

| Validacion | Objetivo |
|---|---|
| `script_local_path` existe | Evitar jobs sin script |
| `python -m py_compile` | Sintaxis Python |
| `flake8 --select=E9,F63,F7,F82` | Errores criticos de lint |
| `GlueContext` | Estructura minima Glue |
| Lectura | El script lee una fuente |
| Escritura | El script escribe una salida |
| `try/except` | Manejo basico de errores |

### Lambda

Archivo:

```text
modules/lambda/validations/validate.sh
```

Valida:

| Validacion | Objetivo |
|---|---|
| `source_path` existe | Evitar Lambda sin codigo |
| `timeout` explicito | Forzar configuracion consciente |
| `memory_size` explicito | Forzar configuracion consciente |
| Python AST + flake8 | Sintaxis/lint para Python |
| `npx eslint` | Lint para Node.js |
| `trufflehog` o grep fallback | Deteccion basica de secretos |

Cada componente puede desactivar validaciones con:

```json
"validations": {
  "enabled": false
}
```

## Versionado Recomendado

Los consumers productivos no deberian depender de `ref=main`. La recomendacion es publicar tags semanticos, por ejemplo:

```text
v1.0.0
v1.1.0
v1.2.0
```

Luego el consumer debe fijar el tag:

```hcl
source = "git::https://github.com/jhonnjc15/artifact3-terraform-templates.git//modules/athena?ref=v1.1.0"
```

## Buenas Practicas Para Nuevos Modulos

1. Mantener entradas pequenas y documentadas.
2. Exponer outputs utiles para consumers.
3. Evitar `local-exec` para validaciones de calidad.
4. Mantener validaciones pre-deploy en `modules/<modulo>/validations`.
5. Evitar cambios destructivos por defecto.
6. Usar tags estables antes de adopcion por consumers.

## Pendientes Recomendados

| Prioridad | Punto |
|---|---|
| Alta | Crear tags de version para consumo estable |
| Media | Robustecer validaciones del modulo Athena |
| Media | Mejorar comportamiento de `merge_existing` cuando la tabla no existe |
| Media | Agregar tests o fixtures de parseo SQL |
| Media | Documentar outputs de cada modulo en README especifico |
| Baja | Agregar ejemplos minimos por modulo |

locals {
  sql_content = try(var.athena.sql_path, null) != null ? file(var.athena.sql_path) : null

  # Auto-detectar operación: CREATE TABLE vs ALTER TABLE
  is_create = try(length(regexall("(?i)\\bCREATE\\s+(EXTERNAL\\s+)?TABLE\\b", local.sql_content)) > 0, false)
  is_alter  = try(length(regexall("(?i)\\bALTER\\s+TABLE\\b", local.sql_content)) > 0, false)
  operation = local.is_alter ? "ALTER" : "CREATE"

  # Extraer valores base del SQL
  # CREATE: ...EXISTS db.table... o TABLE db.table
  # ALTER: TABLE db.table...
  sql_database_name = try(regex("(?i)(?:exists\\s+|table\\s+)(\\w+)\\.", local.sql_content)[0], "default")
  sql_table_name    = try(regex("(?i)(?:exists\\s+|table\\s+)\\w+\\.(\\w+)", local.sql_content)[0], null)
  sql_s3_location   = try(regex("(?i)location\\s+'([^']+)'", local.sql_content)[0], null)

  # Valores finales: prioridad deploy.json -> SQL
  database_name = try(trimspace(var.athena.database_name), "") != "" ? trimspace(var.athena.database_name) : local.sql_database_name
  table_name    = try(trimspace(var.athena.table_name), "") != "" ? trimspace(var.athena.table_name) : local.sql_table_name
  s3_location   = try(trimspace(var.athena.s3_location), "") != "" ? trimspace(var.athena.s3_location) : local.sql_s3_location

  # Parsear todas las TBLPROPERTIES del SQL
  tblproperties_raw = try(regexall("(?im)'([^']+)'\\s*=\\s*'([^']*)'", local.sql_content), [])
  tblproperties     = { for kv in local.tblproperties_raw : kv[0] => kv[1] }

  reserved_table_parameters = toset([
    "table_type",
  ])

  # SerDe / formats (parseados del SQL, usados solo para CREATE)
  serde_library = try(regex("(?i)SERDE\\s+'([^']+)'", local.sql_content)[0], "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe")
  input_format  = try(regex("(?i)INPUTFORMAT\\s+'([^']+)'", local.sql_content)[0], "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat")
  output_format = try(regex("(?i)OUTPUTFORMAT\\s+'([^']+)'", local.sql_content)[0], "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat")

  # Parsear columnas del SQL (aplica tanto para CREATE como ALTER)
  columns_block = try(regex("(?si)\\(\\s*(.+?)\\s*\\)\\s*(?:PARTITIONED|ROW|STORED|LOCATION|TBLPROPERTIES|;|$)", local.sql_content)[0], "")
  columns_raw   = try(regexall("(?im)^\\s*(\\w+)\\s+(\\w+(?:\\([^)]*\\))?)\\s*(?:COMMENT\\s+'([^']*)')?,?\\s*$", local.columns_block), [])
  columns = [
    for c in local.columns_raw : {
      name    = c[0]
      type    = c[1]
      comment = c[2] != "" ? c[2] : null
    }
  ]

  # Parsear partition keys
  partition_block = try(regex("(?si)PARTITIONED\\s+BY\\s+\\((.+?)\\)", local.sql_content)[0], "")
  partitions_raw  = try(regexall("(?im)^\\s*(\\w+)\\s+(\\w+(?:\\([^)]*\\))?)", local.partition_block), [])
  partition_keys = [
    for p in local.partitions_raw : {
      name = p[0]
      type = p[1]
    }
  ]

  description = try(var.athena.description, "Tabla gestionada por Terraform")
}

# Leer tabla existente desde AWS (siempre, para merge aditivo)
data "aws_glue_catalog_table" "existing" {
  count = local.table_name != null && try(var.athena.merge_existing, false) ? 1 : 0

  name          = local.table_name
  database_name = local.database_name
}

locals {
  # Columnas existentes desde AWS (try para primer deploy cuando tabla no existe)
  existing_cols = try([
    for c in data.aws_glue_catalog_table.existing[0].storage_descriptor[0].columns : {
      name    = c.name
      type    = c.type
      comment = try(c.comment, null)
    }
  ], [])

  # Drop/Rename desde deploy.json
  drop_cols  = try(var.athena.column_operations.drop, [])
  rename_map = try(var.athena.column_operations.rename, {})

  # Aplicar drops sobre existentes
  existing_dropped = [for c in local.existing_cols : c if !contains(local.drop_cols, c.name)]

  # Aplicar renames sobre existentes (después de drops)
  existing_renamed = [for c in local.existing_dropped : {
    name    = try(local.rename_map[c.name], c.name)
    type    = c.type
    comment = c.comment
  }]

  existing_renamed_names = toset([for c in local.existing_renamed : c.name])

  # Aplicar drop/rename a las columnas del SQL también
  sql_dropped = [for c in local.columns : c if !contains(local.drop_cols, c.name)]
  sql_renamed = [for c in local.sql_dropped : {
    name    = try(local.rename_map[c.name], c.name)
    type    = c.type
    comment = c.comment
  }]
  sql_renamed_names = toset([for c in local.sql_renamed : c.name])

  # Agregar columnas del SQL (transformado) que no existan (aditivo)
  columns_to_add = [
    for c in local.sql_renamed : c if !contains(local.existing_renamed_names, c.name)
  ]

  # Merge final = existentes (procesadas) + nuevas
  final_columns = concat(local.existing_renamed, local.columns_to_add)

  # Partition keys: existentes + nuevas
  existing_parts       = try(data.aws_glue_catalog_table.existing[0].partition_keys, [])
  existing_part_names  = toset([for p in local.existing_parts : p.name])
  parts_to_add         = [for p in local.partition_keys : p if !contains(local.existing_part_names, p.name)]
  final_partition_keys = concat(local.existing_parts, local.parts_to_add)

  # Preservar metadata existente (con fallback a valores del SQL)
  existing_params   = try(data.aws_glue_catalog_table.existing[0].parameters, {})
  existing_location = try(data.aws_glue_catalog_table.existing[0].storage_descriptor[0].location, null)

  table_parameters = {
    for key, value in merge(
      local.existing_params,
      local.tblproperties,
      try(var.athena.parameters, {})
    ) : key => value
    if !contains(local.reserved_table_parameters, key)
  }
}

# Tabla Glue. La base de datos se gestiona en el root/consumer mediante el bloque
# databases del deploy.json, para permitir muchas tablas en una misma DB.
resource "aws_glue_catalog_table" "this" {
  count = try(var.athena.enabled, false) && local.table_name != null ? 1 : 0

  name          = local.table_name
  database_name = local.database_name
  description   = local.description
  table_type    = "EXTERNAL_TABLE"

  parameters = local.table_parameters

  storage_descriptor {
    location      = local.s3_location
    input_format  = local.input_format
    output_format = local.output_format

    ser_de_info {
      serialization_library = local.serde_library
    }

    dynamic "columns" {
      for_each = local.final_columns
      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = try(columns.value.comment, null)
      }
    }
  }

  dynamic "partition_keys" {
    for_each = local.final_partition_keys
    content {
      name = partition_keys.value.name
      type = partition_keys.value.type
    }
  }
}

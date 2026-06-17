locals {
  sql_content = try(var.athena.sql_path, null) != null ? file(var.athena.sql_path) : null

  # Auto-detectar operación: CREATE TABLE vs ALTER TABLE
  is_create = try(length(regexall("(?i)\\bCREATE\\s+(EXTERNAL\\s+)?TABLE\\b", local.sql_content)) > 0, false)
  is_alter  = try(length(regexall("(?i)\\bALTER\\s+TABLE\\b", local.sql_content)) > 0, false)
  operation = local.is_alter ? "ALTER" : "CREATE"

  # Extraer database_name y table_name del SQL
  # CREATE: ...EXISTS db.table... o TABLE db.table
  # ALTER: TABLE db.table...
  database_name = try(regex("(?i)(?:exists\\s+|table\\s+)(\\w+)\\.", local.sql_content)[0], "default")
  table_name    = try(regex("(?i)(?:exists\\s+|table\\s+)\\w+\\.(\\w+)", local.sql_content)[0], null)

  # Parsear todas las TBLPROPERTIES del SQL
  tblproperties_raw = try(regexall("(?im)'([^']+)'\\s*=\\s*'([^']*)'", local.sql_content), [])
  tblproperties     = { for kv in local.tblproperties_raw : kv[0] => kv[1] }

  # s3_location: prioridad deploy.json → SQL → null
  s3_location = try(var.athena.s3_location, try(regex("(?i)location\\s+'([^']+)'", local.sql_content)[0], null))

  # table_type: prioridad deploy.json → TBLPROPERTIES del SQL → default
  table_type = try(var.athena.table_type, try(local.tblproperties["table_type"], "EXTERNAL_TABLE"))
  is_iceberg = local.table_type == "ICEBERG"

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
  count = local.table_name != null ? 1 : 0

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
  drop_cols   = try(var.athena.column_operations.drop, [])
  rename_map  = try(var.athena.column_operations.rename, {})

  # Aplicar drops sobre existentes
  existing_dropped = [for c in local.existing_cols : c if !contains(local.drop_cols, c.name)]

  # Aplicar renames sobre existentes (después de drops)
  existing_renamed = [for c in local.existing_dropped : {
    name    = try(local.rename_map[c.name], c.name)
    type    = c.type
    comment = c.comment
  }]

  existing_renamed_names = toset([for c in local.existing_renamed : c.name])

  # Agregar columnas del SQL que no existan (aditivo)
  columns_to_add = [
    for c in local.columns : c if !contains(local.existing_renamed_names, c.name)
  ]

  # Merge final = existentes (procesadas) + nuevas
  final_columns = concat(local.existing_renamed, local.columns_to_add)

  # Partition keys: existentes + nuevas
  existing_parts = try(data.aws_glue_catalog_table.existing[0].partition_keys, [])
  existing_part_names = toset([for p in local.existing_parts : p.name])
  parts_to_add = [for p in local.partition_keys : p if !contains(local.existing_part_names, p.name)]
  final_partition_keys = concat(local.existing_parts, local.parts_to_add)

  # Preservar metadata existente (con fallback a valores del SQL)
  existing_params     = try(data.aws_glue_catalog_table.existing[0].parameters, {})
  existing_location   = try(data.aws_glue_catalog_table.existing[0].storage_descriptor[0].location, null)
  existing_table_type = try(data.aws_glue_catalog_table.existing[0].table_type, "EXTERNAL_TABLE")
}

# Base de datos (siempre activa si enabled, no depende de CREATE/ALTER)
resource "aws_glue_catalog_database" "this" {
  count = try(var.athena.enabled, false) ? 1 : 0

  name        = local.database_name
  description = local.description

  tags = var.tags
}

# Tabla Glue
resource "aws_glue_catalog_table" "this" {
  count = try(var.athena.enabled, false) && local.table_name != null ? 1 : 0

  name          = local.table_name
  database_name = local.database_name
  description   = local.description
  table_type    = local.is_iceberg ? "ICEBERG" : local.existing_table_type

  parameters = merge(
    local.existing_params,
    local.tblproperties,
    try(var.athena.parameters, {})
  )

  storage_descriptor {
    location      = local.s3_location
    input_format  = local.is_iceberg ? "org.apache.hadoop.hive.ql.io.iceberg.delegate.IcebergInputFormat" : local.input_format
    output_format = local.is_iceberg ? "org.apache.hadoop.hive.ql.io.iceberg.delegate.IcebergOutputFormat" : local.output_format

    ser_de_info {
      serialization_library = local.is_iceberg ? "org.apache.hadoop.hive.ql.io.iceberg.delegate.IcebergSerDe" : local.serde_library
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

  dynamic "open_table_format_input" {
    for_each = local.is_iceberg ? [1] : []
    content {
      iceberg_input {
        metadata_operation = "CREATE"
        version            = 2
      }
    }
  }

  depends_on = [aws_glue_catalog_database.this]
}

locals {
  sql_content = try(var.athena.sql_path, null) != null ? file(var.athena.sql_path) : null

  database_name = try(regex("(?i)exists\\s+(\\w+)\\.", local.sql_content)[0], "default")
  table_name    = try(regex("(?i)exists\\s+\\w+\\.(\\w+)", local.sql_content)[0], null)
  s3_location   = try(regex("(?i)location\\s+'([^']+)'", local.sql_content)[0], null)

  serde_library = try(regex("(?i)SERDE\\s+'([^']+)'", local.sql_content)[0], "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe")
  input_format  = try(regex("(?i)INPUTFORMAT\\s+'([^']+)'", local.sql_content)[0], "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat")
  output_format = try(regex("(?i)OUTPUTFORMAT\\s+'([^']+)'", local.sql_content)[0], "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat")
  table_type    = try(regex("(?i)'table_type'\\s*=\\s*'(\\w+)'", local.sql_content)[0], "EXTERNAL_TABLE")
  is_iceberg    = local.table_type == "ICEBERG"

  columns_block = try(regex("(?si)\\(\\s*(.+?)\\s*\\)\\s*(?:PARTITIONED|ROW|STORED|LOCATION|TBLPROPERTIES)", local.sql_content)[0], "")
  columns_raw   = try(regexall("(?im)^\\s*(\\w+)\\s+(\\w+(?:\\([^)]*\\))?)\\s*(?:COMMENT\\s+'([^']*)')?,?\\s*$", local.columns_block), [])
  columns = [
    for c in local.columns_raw : {
      name    = c[0]
      type    = c[1]
      comment = c[2] != "" ? c[2] : null
    }
  ]

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

resource "aws_glue_catalog_database" "this" {
  count = try(var.athena.enabled, false) ? 1 : 0

  name        = local.database_name
  description = try(var.athena.description, "Base de datos para tablas Athena")

  tags = var.tags
}

resource "aws_glue_catalog_table" "this" {
  count = try(var.athena.enabled, false) && local.table_name != null ? 1 : 0

  name          = local.table_name
  database_name = local.database_name
  description   = local.description
  table_type    = local.is_iceberg ? "ICEBERG" : "EXTERNAL_TABLE"

  parameters = merge(
    {
      classification = "parquet"
      table_type     = local.table_type
    },
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
      for_each = local.columns
      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = try(columns.value.comment, null)
      }
    }
  }

  dynamic "partition_keys" {
    for_each = local.partition_keys
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

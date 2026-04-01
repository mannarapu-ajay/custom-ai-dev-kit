# Enterprise Dynamic Modeling

Patterns for building data models that adapt to schema changes without breaking downstream consumers.

## Core Principle: Schema-on-Read with Contracts

Never hard-code column names in transformations. Use schema inference + column contracts.

```python
from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import StructType

def apply_transformations(df: DataFrame, config: dict) -> DataFrame:
    """Apply transformations driven by config, not hard-coded columns."""
    for col_name, expr in config.get("derived_columns", {}).items():
        df = df.withColumn(col_name, F.expr(expr))
    return df.select(config["output_columns"])
```

## Dynamic Aggregation Pattern

```python
def dynamic_agg(df: DataFrame, group_by: list[str], metrics: dict[str, str]) -> DataFrame:
    """
    metrics = {"total_revenue": "sum(amount)", "order_count": "count(order_id)"}
    """
    agg_exprs = [F.expr(f"{expr} AS {alias}") for alias, expr in metrics.items()]
    return df.groupBy(*group_by).agg(*agg_exprs)
```

## Late-Arriving Schema Changes

Use Delta Lake schema evolution — never ALTER TABLE manually:

```python
df.write.format("delta") \
    .option("mergeSchema", "true") \      # adds new columns automatically
    .option("overwriteSchema", "false") \ # never drops existing columns
    .mode("append") \
    .saveAsTable("prod_catalog.silver.events")
```

## Column Inventory Pattern (Unity Catalog)

Query what columns exist before building transformations:

```python
def get_available_columns(catalog: str, schema: str, table: str) -> list[str]:
    return [
        row.column_name
        for row in spark.sql(f"""
            SELECT column_name FROM {catalog}.information_schema.columns
            WHERE table_schema = '{schema}' AND table_name = '{table}'
        """).collect()
    ]
```

## Config-Driven Pipeline Template

Store transformation logic in Unity Catalog tables, not code:

```sql
-- Pipeline config table
CREATE TABLE platform_catalog.config.pipeline_transforms (
  pipeline_name  STRING,
  source_table   STRING,
  target_table   STRING,
  filter_expr    STRING,   -- e.g. "status = 'active'"
  select_exprs   STRING,   -- JSON array of "alias:expr" pairs
  partition_cols STRING    -- comma-separated
);
```

```python
def run_pipeline_from_config(pipeline_name: str) -> None:
    config = spark.table("platform_catalog.config.pipeline_transforms") \
        .filter(F.col("pipeline_name") == pipeline_name) \
        .first()
    df = spark.table(config.source_table)
    if config.filter_expr:
        df = df.filter(config.filter_expr)
    df.write.format("delta").mode("overwrite").saveAsTable(config.target_table)
```

## SCD Type 2 — Dynamic Template

```sql
MERGE INTO target t
USING (
  SELECT *, current_timestamp() AS valid_from, true AS is_current FROM source
) s ON t.id = s.id AND t.is_current = true
WHEN MATCHED AND (t.checksum != s.checksum) THEN
  UPDATE SET t.valid_to = current_timestamp(), t.is_current = false
WHEN NOT MATCHED THEN
  INSERT (id, attributes, checksum, valid_from, valid_to, is_current)
  VALUES (s.id, s.attributes, s.checksum, s.valid_from, null, true)
```

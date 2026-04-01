# Enterprise Naming Convention

Follow these naming standards for all Databricks assets created in this workspace.

## Catalogs and Schemas

```
<env>_<domain>_catalog          → prod_finance_catalog
<env>_<domain>_<subdomain>      → dev_sales_raw
```

Environments: `dev`, `staging`, `prod`
Domains: `finance`, `sales`, `marketing`, `data_platform`, `ml`

## Tables

```
<layer>_<entity>_<description>
```

| Layer | Prefix | Example |
|-------|--------|---------|
| Raw ingest | `raw_` | `raw_salesforce_accounts` |
| Cleaned | `silver_` | `silver_accounts_deduped` |
| Business | `gold_` | `gold_monthly_revenue` |
| ML features | `feat_` | `feat_customer_ltv` |

## Delta Tables — Always Set These Properties

```sql
CREATE TABLE prod_finance_catalog.gold.monthly_revenue (
  ...
)
USING DELTA
TBLPROPERTIES (
  'delta.enableChangeDataFeed' = 'true',
  'delta.autoOptimize.optimizeWrite' = 'true',
  'delta.autoOptimize.autoCompact' = 'true',
  'owner' = 'data-platform-team',
  'domain' = 'finance'
);
```

## Jobs and Pipelines

```
<team>_<frequency>_<description>
finance_daily_revenue_aggregation
ml_hourly_feature_refresh
```

## Clusters

All clusters must have tags:
```json
{ "team": "...", "env": "...", "cost_center": "CC-XXXX" }
```

## Notebooks

```
/Repos/<team>/<project>/notebooks/<layer>/<name>
/Repos/finance/revenue-pipeline/notebooks/silver/clean_transactions
```

## Python / PySpark

- Snake case for all variables and functions: `customer_id`, `compute_ltv()`
- Class names PascalCase: `RevenueAggregator`
- Constants uppercase: `MAX_RETRY_COUNT = 3`
- No magic strings — use constants or configs

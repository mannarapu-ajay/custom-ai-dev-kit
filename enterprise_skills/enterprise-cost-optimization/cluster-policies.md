# Enterprise Cluster Policies

## Standard Policy: Interactive Development

Enforces cost guardrails on all-purpose clusters used by engineers.

```json
{
  "spark_version": {
    "type": "regex",
    "pattern": "^(1[4-9]|[2-9]\\d)\\..*-scala2\\.12$",
    "defaultValue": "15.4.x-scala2.12"
  },
  "autotermination_minutes": {
    "type": "range",
    "minValue": 10,
    "maxValue": 120,
    "defaultValue": 30
  },
  "node_type_id": {
    "type": "allowlist",
    "values": ["m5d.large", "m5d.xlarge", "m5d.2xlarge"],
    "defaultValue": "m5d.large"
  },
  "num_workers": {
    "type": "range",
    "minValue": 0,
    "maxValue": 8,
    "defaultValue": 2
  },
  "custom_tags.cost_center": {
    "type": "regex",
    "pattern": "^CC-[0-9]{4}$"
  }
}
```

## Policy: Job Clusters (Production)

For scheduled jobs — ephemeral, no idle cost.

```json
{
  "cluster_type": {
    "type": "fixed",
    "value": "job"
  },
  "spark_version": {
    "type": "regex",
    "pattern": "^15\\..*-scala2\\.12$"
  },
  "runtime_engine": {
    "type": "fixed",
    "value": "PHOTON"
  }
}
```

## Cost Attribution Tags

All clusters MUST have these custom tags:

| Tag Key      | Format       | Example          |
|-------------|-------------|-----------------|
| cost_center  | CC-XXXX     | CC-1234          |
| team         | lowercase   | data-engineering |
| environment  | enum        | dev/staging/prod |
| owner        | email       | user@acme.com    |

---
name: enterprise-data-governance
version: "1.0.0"
profiles:
  - core
  - data-engineer
  - analyst
description: >
  Enterprise-specific data governance patterns, PII classification rules,
  Unity Catalog tagging standards, and data retention policies.
---

# Enterprise Data Governance

This skill extends the Databricks Unity Catalog skill with enterprise-specific
governance requirements mandated by the Legal and Compliance teams.

## Scope

- PII data classification and tagging in Unity Catalog
- Data retention schedules (defined in `data-classification.md`)
- Audit logging requirements
- Row-level security patterns
- Column masking templates

## Quick Reference

When working with data assets in this enterprise:

1. **Always tag PII columns** using the `pii_type` tag (see data-classification.md)
2. **Apply retention policies** at table creation time
3. **Use RLS templates** for multi-tenant data access patterns
4. **Audit log** all DDL operations via the standard audit bundle

## Integration with Databricks Skills

This skill is designed to work alongside:
- `databricks-unity-catalog` — for Unity Catalog operations
- `databricks-dbsql` — for SQL-based governance queries
- `databricks-model-serving` — for governed AI endpoint deployment

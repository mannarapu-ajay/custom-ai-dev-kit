# Enterprise Data Classification

## PII Classification Levels

| Level | Tag Value    | Examples                          | Masking Required |
|-------|-------------|-----------------------------------|-----------------|
| L1    | `pii:l1`    | Name, email, phone                | Yes — always    |
| L2    | `pii:l2`    | Address, DOB                      | Yes — always    |
| L3    | `pii:l3`    | SSN, financial account numbers    | Yes — encrypt   |
| None  | `pii:none`  | Product IDs, timestamps           | No              |

## Applying Tags in Unity Catalog

```sql
-- Tag a column at table creation
CREATE TABLE acme_catalog.customer_data.orders (
  order_id    BIGINT,
  customer_id BIGINT,
  email       STRING COMMENT 'TAGS: pii:l1',
  ssn         STRING COMMENT 'TAGS: pii:l3'
);

-- Apply tag to existing column
ALTER TABLE acme_catalog.customer_data.orders
  ALTER COLUMN email SET TAGS ('pii_type' = 'l1', 'retention_days' = '365');
```

## Retention Schedule

| Data Category    | Retention  | Policy Reference |
|-----------------|-----------|-----------------|
| Transaction data | 7 years   | POL-FINANCE-001  |
| User PII         | 3 years   | POL-PRIVACY-003  |
| Audit logs       | 10 years  | POL-AUDIT-001    |
| ML feature data  | 2 years   | POL-ML-002       |

## Row-Level Security Template

```sql
-- Standard multi-tenant RLS using session context
CREATE ROW ACCESS POLICY acme_tenant_isolation
AS (tenant_id STRING)
RETURNS BOOLEAN ->
  current_user() IN (
    SELECT email FROM acme_catalog.iam.tenant_users
    WHERE tenant = tenant_id
  );

ALTER TABLE acme_catalog.silver.events
  ADD ROW ACCESS POLICY acme_tenant_isolation ON (tenant_id);
```

## Column Masking Template

```sql
-- Mask PII for non-privileged users
CREATE MASKING POLICY acme_pii_mask
AS (val STRING) RETURNS STRING ->
  CASE
    WHEN is_account_group_member('pii-readers') THEN val
    ELSE '***REDACTED***'
  END;
```

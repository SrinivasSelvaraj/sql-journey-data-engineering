---
date: 2026-08-23
phase: cloud
topic: Unity Catalog and fine-grained data governance
---

# Unity Catalog and fine-grained data governance

*Cloud platforms and storage*

## Concept

Unity Catalog (UC) is Databricks' centralized metadata and governance layer that enforces fine-grained access control across databases, tables, and columns. It sits above the metastore and lets you define who can read, write, or execute at object level—critical when multiple teams or departments access the same cloud storage. Without it, access control defaults to file-system permissions or cloud IAM, which is coarse-grained: you either have access to an entire S3 bucket or nothing.

Why it matters: in multi-tenant analytics environments, data teams often need to share tables but hide sensitive columns (e.g., salary details, PII). UC lets you grant `SELECT` on a table but deny access to specific columns, apply row-level filters, or audit exactly who queried what. Query slowness often roots in unindexed joins across improperly partitioned tables or cross-cluster broadcast; UC's lineage and data access logs help you trace which queries touched sensitive data and optimize based on actual usage patterns.

Breaks without it: compliance violations (GDPR, HIPAA require column-level access logs), untracked data leaks, and costly over-provisioning of separate clusters just to isolate datasets.

## Practice

**Problem:** Your analytics team shares `job_postings_fact`. Finance should see salary data, but HR should not; all teams need to see job titles and locations. You need to enforce this without creating duplicate tables.

```sql
-- 1. Create the base table in UC (requires UC-enabled catalog and schema)
CREATE TABLE main.analytics.job_postings_fact (
  job_id INT,
  job_title_short STRING,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location STRING
)
USING DELTA;

-- 2. Grant read access to both teams on the table itself
GRANT SELECT ON TABLE main.analytics.job_postings_fact TO `finance-team@company.com`;
GRANT SELECT ON TABLE main.analytics.job_postings_fact TO `hr-team@company.com`;

-- 3. Deny HR access to the salary column using column-level masking
ALTER TABLE main.analytics.job_postings_fact
ALTER COLUMN salary_year_avg SET MASK salary_mask();

-- 4. Create a custom masking function that redacts for non-Finance users
CREATE FUNCTION main.analytics.salary_mask()
RETURNS INT
RETURN CASE 
  WHEN is_member('finance-team@company.com') THEN salary_year_avg
  ELSE NULL 
END;

-- 5. Verify HR sees nulls, Finance sees values
SELECT job_title_short, salary_year_avg, job_location 
FROM main.analytics.job_postings_fact 
WHERE job_posted_date >= '2024-01-01';
-- HR result: salary_year_avg = NULL for all rows
-- Finance result: salary_year_avg = actual values
```

## Notes

- **Column masking vs. row filtering:** masking hides data in columns; row filters exclude entire rows. Use masking for sensitive attributes in shared tables, row filters for tenant isolation.
- **Audit logs are queryable:** UC logs all access to `system.access.audit_logs`; query it to find who accessed salary data and when—essential for compliance and cost attribution.
- **Clusters must use UC mode:** standard compute cannot enforce UC policies. Use SQL warehouses or UC-enabled all-purpose clusters; this impacts billing (UC adds per-GB scanned overhead).
- **Lineage and cost tracking:** enable `spark.databricks.dataLineage.enabled` to track which queries touched which assets; combine with cloud storage cost attribution to answer "why did Finance's queries cost 40% of our budget?"
- **Adjacent: Delta Lake ACID transactions, Databricks workspace identity federation, cloud IAM (S3 bucket policies, Azure RBAC) as fallback.**

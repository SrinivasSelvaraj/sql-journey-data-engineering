---
date: 2026-10-02
phase: reliability
topic: Schema monitoring and column addition detection
---

# Schema monitoring and column addition detection

*Quality, reliability and the professional layer*

## Concept

Schema monitoring is the practice of systematically tracking structural changes to tables—new columns, dropped columns, type changes, constraint additions—and alerting when they occur. Without it, downstream consumers discover breakage at runtime: a job posting pipeline suddenly fails because `job_work_from_home` was added as non-nullable, or a reporting layer silently produces incorrect results because salary data changed from `DECIMAL(10,2)` to `INTEGER`.

This becomes critical in mature data environments where multiple teams depend on shared tables. The person who owns a pipeline is responsible not just for moving data, but for detecting when upstream schemas change and either adapting gracefully or raising alarms. This separates script-writers from reliability engineers.

Practical monitoring typically involves querying information schema tables (`INFORMATION_SCHEMA.COLUMNS`, `pg_catalog`, etc.) on a schedule, storing the results, and comparing against a baseline. A daily dbt test or Airflow task that snapshots column metadata, then checks for drift, catches problems before users do.

## Practice

**Problem:** The `job_postings_fact` table unexpectedly receives two new columns: `job_posting_source` (VARCHAR) and `job_application_count` (INT). Your downstream reports assume the schema hasn't changed and will now fail or produce silent logic errors if they depend on column position or expect specific fields.

**Solution:**

```sql
-- Snapshot current schema (run daily, store results in a monitoring table)
INSERT INTO schema_monitoring.column_snapshots (table_name, snapshot_date, column_list, column_count)
SELECT 
  'job_postings_fact' AS table_name,
  CURRENT_DATE,
  STRING_AGG(column_name || ':' || data_type, ', ' ORDER BY ordinal_position),
  COUNT(*) AS column_count
FROM INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'public' AND table_name = 'job_postings_fact';

-- Detect schema drift (compare today vs. yesterday)
SELECT 
  current.column_list,
  previous.column_list,
  current.column_count - previous.column_count AS column_delta,
  CASE WHEN current.column_count > previous.column_count THEN 'COLUMNS_ADDED'
       WHEN current.column_count < previous.column_count THEN 'COLUMNS_DROPPED'
       WHEN current.column_list != previous.column_list THEN 'TYPE_OR_ORDER_CHANGE'
       ELSE 'NO_CHANGE' END AS drift_type
FROM schema_monitoring.column_snapshots current
LEFT JOIN schema_monitoring.column_snapshots previous
  ON previous.table_name = current.table_name 
  AND previous.snapshot_date = CURRENT_DATE - INTERVAL '1 day'
WHERE current.table_name = 'job_postings_fact'
  AND current.snapshot_date = CURRENT_DATE;
```

## Notes

- **Silent failures are worse than loud ones**: A missing column detection alert is better than a report that runs successfully but excludes important data. Instrument early.
- **Schema as code**: Store your expected schema in version control (dbt `sources`, JSON schema docs, or database DDL). Compare reality against the source of truth, not just yesterday's snapshot.
- **Connects to contract testing**: Similar mindset to API contracts—both consumer and producer agree on shape. A breaking schema change is a broken contract.
- **Watch ordinal position**: Column order changes silently break `SELECT *` logic and position-based imports. Always select columns by name, not position.
- **Revisit constraint monitoring separately**: NOT NULL additions, foreign keys, and check constraints are schema changes too, but often warrant separate alerting urgency than new optional columns.

---
date: 2026-08-23
phase: pipelines
topic: Handling upstream schema changes automatically
---

# Handling upstream schema changes automatically

*Pipelines and orchestration*

## Concept

Upstream schema changes—new columns, renamed fields, type conversions, dropped attributes—break pipelines silently or loudly depending on how you've written them. A pipeline that assumes exact column order or presence fails on the first schema drift, leaving you debugging production at 2 AM. Handling changes automatically means your pipeline either adapts gracefully, alerts you with context, or fails in a way that's recoverable and informative.

This matters most when you depend on tables you don't own (vendor APIs, third-party data lakes, upstream teams' output). Without explicit schema tracking, you won't know if a new column was added (ignored, wasting potential data) or if a column was dropped (your join breaks, your count logic silently returns NULL). The cost compounds: a silently corrupted fact table infects downstream analytics for weeks.

The solution combines three layers: schema validation before load, column-safe selection (explicit or qualified), and assertion tests that catch missing or unexpected fields early. This transforms schema changes from silent data loss into loud, actionable failures or automated adaptation.

## Practice

**Problem:** `job_postings_fact` gains two new columns (`job_salary_currency` and `job_posting_id`), and `job_work_from_home` is renamed to `remote_eligible`. Your downstream pipeline selects `SELECT * FROM job_postings_fact` to load into a warehouse, then joins on `job_work_from_home`. The `SELECT *` will pick up the new columns (wasting storage and processing), and the join will fail silently or throw an error mid-pipeline.

**Solution:**

```sql
-- 1. Validate schema before load
WITH schema_check AS (
  SELECT 
    CASE 
      WHEN 'remote_eligible' IN (SELECT column_name FROM information_schema.columns WHERE table_name = 'job_postings_fact')
        THEN 'remote_eligible'
      WHEN 'job_work_from_home' IN (SELECT column_name FROM information_schema.columns WHERE table_name = 'job_postings_fact')
        THEN 'job_work_from_home'
      ELSE NULL
    END AS remote_column
  FROM (SELECT 1) t
)
-- 2. Select explicitly, handle renamed column
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  COALESCE(remote_eligible, job_work_from_home) AS is_remote,
  job_posted_date,
  job_location
FROM job_postings_fact
WHERE (SELECT remote_column FROM schema_check) IS NOT NULL;

-- 3. Assertion: fail loud if expected columns missing
SELECT 
  CASE 
    WHEN COUNT(DISTINCT column_name) < 6 THEN ERROR('Schema mismatch: missing expected columns')
    ELSE 'Schema valid'
  END
FROM information_schema.columns
WHERE table_name = 'job_postings_fact'
  AND column_name IN ('job_id', 'job_title_short', 'salary_year_avg', 'job_posted_date', 'job_location');
```

## Notes

- **Explicit > implicit:** Never use `SELECT *` in production pipelines. Name columns explicitly, even if it feels verbose. This catches renames and drops immediately rather than silently changing output shape.
- **Schema registry pattern:** Store expected schema (column names, types, nullability) in a metadata table or config file. Compare at pipeline start; fail or alert if mismatch. This is cheaper than debugging corrupt data downstream.
- **Coalesce for safe renames:** When upstream renames a column you depend on, use `COALESCE(new_name, old_name)` during a transition window. Pair with monitoring to catch when old column finally disappears.
- **Test assertions must run before transforms:** Schema validation (existence, type, cardinality checks) runs as the first step of a pipeline, not after loading. This prevents partial loads.
- **Connects to:** data quality rules (dbt tests, Great Expectations), orchestration idempotence (rerun safely), and observability (alert on schema drift, not just on data volume anomalies).

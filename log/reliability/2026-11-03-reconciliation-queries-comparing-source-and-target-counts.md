---
date: 2026-11-03
phase: reliability
topic: Reconciliation queries: comparing source and target counts
---

# Reconciliation queries: comparing source and target counts

*Quality, reliability and the professional layer*

## Concept

Reconciliation queries verify that data moved correctly from source to target by comparing counts, sums, and other aggregate metrics. They answer the question: "Did all the data get there, and is it correct?" Without them, you ship pipelines that appear successful but silently lose or corrupt rows—often discovered weeks later when business users notice discrepancies in reports.

This is the difference between a working pipeline and a trustworthy one. A join that silently fails, a filter applied twice, a truncate that happens before the insert—reconciliation catches these before they reach stakeholders. It's especially critical after transformations where rows can multiply (bad joins) or disappear (overly strict filtering).

Reconciliation lives in the "professional layer" because it requires discipline: running the same query pattern repeatedly, setting thresholds you'll actually alert on, and treating mismatches as incidents rather than data quality quirks to investigate later.

## Practice

**Problem:** Your job_postings_fact table is loaded nightly from a source system. You need to verify that all records arrived, that no salary values were nulled out unexpectedly, and that the date range matches what you expect.

```sql
-- Reconciliation query: source vs. target
WITH source_counts AS (
  SELECT
    COUNT(*) as row_count,
    COUNT(DISTINCT job_id) as unique_jobs,
    COUNT(CASE WHEN salary_year_avg IS NOT NULL THEN 1 END) as non_null_salaries,
    MIN(job_posted_date) as earliest_date,
    MAX(job_posted_date) as latest_date
  FROM raw.job_postings_source
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
),
target_counts AS (
  SELECT
    COUNT(*) as row_count,
    COUNT(DISTINCT job_id) as unique_jobs,
    COUNT(CASE WHEN salary_year_avg IS NOT NULL THEN 1 END) as non_null_salaries,
    MIN(job_posted_date) as earliest_date,
    MAX(job_posted_date) as latest_date
  FROM analytics.job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
)
SELECT
  s.row_count as source_rows,
  t.row_count as target_rows,
  (s.row_count - t.row_count) as row_diff,
  CASE WHEN s.row_count = t.row_count THEN '✓' ELSE '✗ MISMATCH' END as row_check,
  s.non_null_salaries as source_salaries_filled,
  t.non_null_salaries as target_salaries_filled,
  CASE WHEN s.non_null_salaries = t.non_null_salaries THEN '✓' ELSE '✗ NULLS INTRODUCED' END as salary_check,
  s.earliest_date as source_min_date,
  t.earliest_date as target_min_date
FROM source_counts s, target_counts t;
```

Run this after every load. If any check fails, halt downstream processing and investigate the pipeline logs.

## Notes

- **Don't just count rows.** Row counts can match while data is corrupted. Always reconcile on key columns: distinct IDs, sums of numeric fields, null counts, date ranges. Triangulate.
- **Set explicit thresholds and alert on them.** Decide: is a 1-row difference acceptable? 0.1%? Hard fail? Codify this in your orchestration tool (dbt tests, Airflow sensors, dbt-expectations) rather than eyeballing results.
- **Reconciliation queries live in version control and run automatically.** Treat them like tests. If you're running them manually in a notebook, you'll skip them under deadline pressure.
- **Cross-check with downstream metrics.** A reconciliation query passing doesn't mean the schema is right—validate that sums, averages, and distinct counts match what business teams expect in their dashboards.
- **Adjacent skills:** Data lineage (tracing where rows are lost), anomaly detection (thresholds that adapt over time), and dbt source freshness checks (ensuring source data exists before you load it).

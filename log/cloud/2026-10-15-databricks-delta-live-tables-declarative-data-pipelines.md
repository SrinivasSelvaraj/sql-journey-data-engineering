---
date: 2026-10-15
phase: cloud
topic: Databricks Delta Live Tables: declarative data pipelines
---

# Databricks Delta Live Tables: declarative data pipelines

*Cloud platforms and storage*

## Concept

Delta Live Tables (DLT) is Databricks' declarative framework for building reliable, maintainable data pipelines using SQL or Python. Instead of writing imperative orchestration logic (if this table exists, run this job, then refresh that one), you declare *what* tables should exist and *how* they are computed; DLT handles scheduling, retries, data quality enforcement, and lineage. This matters because production pipelines fail silently—a join on stale data, a schema drift mid-pipeline, or a downstream dependency missing invalidates everything downstream. Without DLT, you're manually checking freshness, testing data quality with assertions after the fact, and losing visibility into which table caused the failure. DLT's declarative model enforces expectations (constraints, not-null checks, row counts) *during* the pipeline run, stops early on contract violations, and surfaces lineage so you know why a query is slow (missing upstream refresh) rather than guessing.

## Practice

**Problem:** You have a `job_postings_fact` table with daily inserts. You need to create a curated layer that:
- Filters to only US-based remote jobs with salary > $100k
- Adds a column for compensation tier (entry, mid, senior) based on salary ranges
- Ensures no nulls in critical fields and fails the pipeline if salary_year_avg has >5% missing values

**Solution:**

```sql
CREATE OR REPLACE TABLE live.job_postings_curated AS
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_location,
  CASE
    WHEN salary_year_avg < 70000 THEN 'entry'
    WHEN salary_year_avg < 120000 THEN 'mid'
    ELSE 'senior'
  END AS compensation_tier,
  job_posted_date
FROM live.job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_location LIKE '%US%'
  AND salary_year_avg > 100000;

CREATE OR REPLACE EXPECTATION salary_not_null AS
  SELECT * FROM live.job_postings_curated WHERE salary_year_avg IS NULL;

CREATE OR REPLACE EXPECTATION salary_completeness AS
  SELECT * FROM live.job_postings_fact
  WHERE (COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) / COUNT(*)) > 0.05;
```

The pipeline will auto-refresh, apply filters, compute tiers, and fail loudly if nulls exceed 5%—no manual validation needed.

## Notes

- **CONSTRAINT vs. EXPECTATION:** constraints block bad rows; expectations log violations but let pipelines continue. Use constraints for data contracts you cannot break (primary keys), expectations for quality thresholds you monitor.
- **Freshness and compute cost:** DLT pipelines run on Databricks clusters; declaring *all* dependencies upfront lets Databricks optimize DAG execution and skip unnecessary reruns. Review the cost breakdown per table in the DLT UI—a slow query often means an upstream table is refreshing too frequently or a join is broadcasting a large table needlessly.
- **Schema evolution & versioning:** DLT catches schema drift (e.g., a new column appears unexpectedly). Use `MERGE` for incremental updates rather than full rewrites to control costs and latency.
- **Testing in DLT:** expectations are not unit tests; validate logic in a sandbox cluster first, then promote to production pipelines. DLT is orchestration + quality, not a substitute for development.
- **Adjacent skill:** understand Databricks table formats (Delta, Iceberg) and how to read query plans (EXPLAIN) to spot why a pipeline stage is slow—often it's a missing index or a shuffle you didn't intend.

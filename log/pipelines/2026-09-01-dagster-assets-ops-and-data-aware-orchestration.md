---
date: 2026-09-01
phase: pipelines
topic: Dagster: assets, ops and data-aware orchestration
---

# Dagster: assets, ops and data-aware orchestration

*Pipelines and orchestration*

## Concept

Dagster separates **ops** (individual compute units) from **assets** (data objects with lineage). Assets let you model what data *exists* and how it was produced, while ops define discrete transformations. This distinction matters because pipelines often fail mid-execution or need partial reruns—without clear asset boundaries, you lose the ability to know which data is stale, which transformations succeeded, and what to recompute.

Data-aware orchestration means the scheduler understands your data dependencies, not just task dependencies. When a source table updates, Dagster can automatically rerun only the downstream assets that depend on it, rather than rerunning your entire pipeline. This prevents wasted computation and makes debugging easier: you can inspect intermediate assets to see exactly where logic broke.

Without this layer, you either manually track what depends on what (fragile at scale) or rebuild everything (slow and expensive). Dagster's asset graph forces you to be explicit about lineage, which is what makes it possible to "fail loudly" (catch issues early in the graph) and "rerun safely" (only recompute what changed).

## Practice

**Problem:** You have raw job postings ingested daily into a staging table. You need to create a cleaned fact table, then calculate salary statistics by job title. If the raw data arrives late or cleaning logic changes, you want to recompute only the affected assets without re-ingesting.

```sql
-- Raw ingestion (external, but declared as asset)
CREATE TABLE job_postings_raw AS
SELECT * FROM external_api WHERE job_posted_date = CURRENT_DATE;

-- Cleaned fact table (op 1: depends on raw)
CREATE TABLE job_postings_fact AS
SELECT 
  job_id,
  TRIM(job_title) AS job_title_short,
  CAST(salary_year_avg AS DECIMAL(10,2)) AS salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_raw
WHERE job_id IS NOT NULL 
  AND salary_year_avg > 0
  AND job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY;

-- Statistics layer (op 2: depends on fact)
CREATE TABLE job_title_salary_stats AS
SELECT 
  job_title_short,
  COUNT(*) AS job_count,
  AVG(salary_year_avg) AS avg_salary,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) AS median_salary,
  MAX(job_posted_date) AS last_updated
FROM job_postings_fact
GROUP BY job_title_short;
```

In Dagster, you'd declare `job_postings_raw`, `job_postings_fact`, and `job_title_salary_stats` as separate `@asset`-decorated functions. If raw data updates, only fact and stats recompute. If cleaning logic changes, only fact and stats recompute—raw stays untouched.

## Notes

- **Confusing ops with assets:** ops are the *recipe* (code that runs), assets are the *ingredients and dishes* (data produced). One op can produce multiple assets; one asset can depend on multiple ops. Model assets, wire ops.
- **Forgetting intermediate materialization:** if you don't materialize intermediate assets (write them to storage), you can't inspect them or reuse them in other jobs. Materialization adds I/O cost but buys debuggability.
- **Asset versioning and time-travel:** Dagster can track asset versions and re-materialize historical slices; connects to slowly-changing dimensions, audit trails, and rollback scenarios in production data warehouses.
- **Sensor and resource coupling:** assets should not hardcode database credentials or file paths—use Dagster resources and IO managers to abstract storage, making assets portable across dev/prod.
- **Related: data quality checks** (asset observations, freshness policies) and **dynamic orchestration** (asset partitions for time-series or categorical slicing), both layer naturally on top of the asset graph.

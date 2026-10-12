---
date: 2026-10-12
phase: pipelines
topic: Dagster assets and definitions for functional DAGs
---

# Dagster assets and definitions for functional DAGs

*Pipelines and orchestration*

## Concept

Dagster assets are the foundation of declarative, functional DAGs: each asset is an immutable output of a computation, defined by a pure function that depends explicitly on other assets. Unlike traditional task-based DAGs (where you wire up tasks), asset-based DAGs ask "what does this data represent?" and "what does it depend on?"—making lineage transparent and reruns safe. When a downstream asset fails, you know exactly which upstream assets to recompute; when you rerun, Dagster skips unchanged dependencies by default.

This matters most when your pipeline is fragile or data-dependent. Without explicit asset definitions, a task failure leaves you guessing whether to rerun the whole DAG or just one step; without functional purity, rerunning the same task twice may produce different results, making debugging impossible. Dagster assets force you to name each logical transformation, version its inputs, and declare dependencies—so the system can fail loudly (errors are tied to specific assets) and rerun safely (no hidden side effects).

## Practice

**Problem:** You have raw job postings ingested daily. You need to compute average salary per job title, then flag any job title where the average dropped >10% from the prior day. Without asset definition, a rerun after failure may use stale reference data; with assets, each step is deterministic and only recomputes if inputs change.

```sql
-- Asset 1: daily job postings snapshot
CREATE OR REPLACE TABLE job_postings_fact AS
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_posted_date
FROM raw_postings
WHERE job_posted_date = CURRENT_DATE;

-- Asset 2: daily salary averages by title
CREATE OR REPLACE TABLE salary_by_title_daily AS
SELECT 
  job_title_short,
  job_posted_date,
  ROUND(AVG(salary_year_avg), 2) as avg_salary,
  COUNT(*) as job_count
FROM job_postings_fact
GROUP BY job_title_short, job_posted_date;

-- Asset 3: salary change detection (depends on current + previous day)
CREATE OR REPLACE TABLE salary_drops AS
SELECT 
  today.job_title_short,
  today.job_posted_date,
  today.avg_salary as current_avg,
  yesterday.avg_salary as previous_avg,
  ROUND(((today.avg_salary - yesterday.avg_salary) / yesterday.avg_salary) * 100, 2) as pct_change
FROM salary_by_title_daily today
LEFT JOIN salary_by_title_daily yesterday
  ON today.job_title_short = yesterday.job_title_short
  AND today.job_posted_date = yesterday.job_posted_date + 1
WHERE yesterday.avg_salary IS NOT NULL
  AND ((today.avg_salary - yesterday.avg_salary) / yesterday.avg_salary) < -0.10;
```

Each asset is a pure table definition with clear dependencies (Asset 3 explicitly depends on Asset 2, Asset 2 on Asset 1). A failed rerun only recomputes affected assets.

## Notes

- **Pure functions only:** avoid randomness, API calls, or "current timestamp" inside asset definitions—wrap these in `@resource` or pass as parameters.
- **Naming is lineage:** asset names should answer "what is this data?"—`salary_by_title_daily` is better than `transform_3`.
- **Backfills and time windows:** when assets represent time-partitioned data, use `@asset` with `partitions_def` so Dagster knows how to backfill historical runs safely.
- **Connects to:** asset materialization (when to compute), asset sensors (trigger on upstream completion), dynamic outputs (fan-out pipelines), and data quality checks (attach tests to assets).
- **Revisit:** the difference between imperative task graphs (`@job`) and declarative asset graphs; how to mock assets in unit tests; asset versioning strategies for schema changes.

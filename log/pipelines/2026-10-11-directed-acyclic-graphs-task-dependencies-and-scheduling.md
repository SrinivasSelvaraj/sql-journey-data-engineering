---
date: 2026-10-11
phase: pipelines
topic: Directed acyclic graphs: task dependencies and scheduling
---

# Directed acyclic graphs: task dependencies and scheduling

*Pipelines and orchestration*

## Concept

A directed acyclic graph (DAG) is a representation of task dependencies where each node is a unit of work and edges point from prerequisite tasks to dependent tasks. The "acyclic" property ensures no circular dependencies exist—every task eventually completes without waiting on itself. In data pipelines, DAGs let orchestrators like Airflow, dbt, or Dagster understand which tasks can run in parallel, which must wait, and what order guarantees correctness.

DAGs matter because they're the difference between a pipeline that silently produces wrong answers and one that fails loudly when dependencies break. Without explicit DAG structure, you risk running a transformation before its input data arrives, or rerunning only part of a pipeline and leaving downstream consumers with stale or inconsistent views. A well-defined DAG also makes recovery predictable: when task C fails, you know exactly which tasks to rerun (C and everything downstream) and which to skip (everything upstream that already succeeded).

Pipelines without DAGs often resort to crude timing logic—"wait 30 seconds for the previous job"—which fails under load and hides real dependency problems. Explicit DAGs force you to declare intent, catch misconfiguration before runtime, and enable safe retries and partial reruns that preserve data consistency.

## Practice

**Problem:** Build a pipeline that enriches raw job postings with salary statistics by location, but only after the source data has been validated and deduplicated. The enrichment step requires location-level aggregates computed from the cleaned data.

```sql
-- Task 1: Load and validate raw job postings
CREATE TEMP TABLE raw_validated AS
SELECT * FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
  AND job_id IS NOT NULL
  AND salary_year_avg > 0;

-- Task 2: Deduplicate (depends on Task 1)
CREATE TABLE job_postings_dedup AS
SELECT DISTINCT ON (job_id) *
FROM raw_validated
ORDER BY job_id, job_posted_date DESC;

-- Task 3: Compute location-level salary aggregates (depends on Task 2)
CREATE TABLE salary_stats_by_location AS
SELECT 
  job_location,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as median_salary,
  MAX(salary_year_avg) as max_salary
FROM job_postings_dedup
GROUP BY job_location;

-- Task 4: Enrich postings with location stats (depends on Tasks 2 and 3)
CREATE TABLE job_postings_enriched AS
SELECT 
  j.job_id,
  j.job_title_short,
  j.salary_year_avg,
  j.job_work_from_home,
  j.job_posted_date,
  j.job_location,
  s.avg_salary as location_avg_salary,
  s.median_salary as location_median_salary,
  ROUND(((j.salary_year_avg - s.avg_salary) / s.avg_salary * 100)::NUMERIC, 2) as pct_above_location_avg
FROM job_postings_dedup j
LEFT JOIN salary_stats_by_location s ON j.job_location = s.job_location;
```

**DAG structure:** Task 1 → Task 2 → Task 4; Task 2 → Task 3 → Task 4. Tasks 2 and 3 can run in parallel after Task 1 succeeds. Task 4 waits for both Task 2 and Task 3.

## Notes

- **Circular dependency trap:** Avoid patterns where Task A waits for Task B's output while Task B indirectly reads Task A's results; structure queries to flow in one direction only.
- **Fan-out and fan-in:** Multiple tasks can depend on a single upstream task (fan-out), and a single task can depend on many upstream tasks (fan-in)—this is expected and safe in a DAG.
- **Idempotency is prerequisite:** Each task must be safe to rerun without duplicate inserts or state corruption; pair DAG structure with CREATE TABLE AS (not INSERT) or idempotent upserts.
- **Testing the DAG:** Validate the graph structure itself before runtime—check for cycles, missing dependencies, and orphaned tasks; orchestrators can auto-detect these.
- **Connect to:** dbt's `ref()` and `source()` macros build DAGs automatically; Airflow's task_group and sensor patterns extend DAGs with conditional logic and cross-pipeline dependencies.

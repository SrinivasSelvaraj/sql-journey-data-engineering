---
date: 2026-10-28
phase: pipelines
topic: DAG definition and task dependency patterns
---

# DAG definition and task dependency patterns

*Pipelines and orchestration*

## Concept

A DAG (Directed Acyclic Graph) is an explicit declaration of which tasks must run before others, ensuring work happens in the right order without circular dependencies. In orchestration tools like Airbnb's Airflow, dbt, or Prefect, you define tasks as nodes and dependencies as edges—the framework then parallelizes what can run in parallel and blocks what must wait. This matters because without clear dependency definition, you risk data arriving before transformation is complete, retrying tasks that didn't fail, or recomputing expensive work unnecessarily.

Task dependency patterns determine how sensitive your pipeline is to failures and how quickly you can recover. Common patterns include linear chains (A→B→C), fan-out (A→B,C,D), fan-in (B,C,D→A), and diamonds (A→B,C→D). Each pattern has different implications for partial reruns: a diamond lets you retry D without re-running B and C if D failed; a chain means one failure stops everything downstream. Without explicit dependencies, you either hardcode waits (slow, fragile) or run tasks concurrently and hope (noisy errors, data inconsistency).

## Practice

**Problem:** Load job postings, enrich with salary benchmarks from a reference table, then aggregate location-level statistics. If the reference table load fails, the enrichment should not run. If enrichment fails, aggregation should not run. You also want to rerun just the aggregation without reloading everything if you fix a grouping bug.

```sql
-- Task 1: Load raw job_postings_fact
INSERT INTO job_postings_fact 
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM source_db.job_postings;

-- Task 2: Create salary_benchmarks reference (depends on Task 1 implicit via schema, but explicit: depends_on=['load_raw_postings'])
INSERT INTO salary_benchmarks_by_role
SELECT job_title_short, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as p50_salary
FROM job_postings_fact
GROUP BY job_title_short;

-- Task 3: Enrich postings with benchmark comparison (depends_on=['load_salary_benchmarks'])
INSERT INTO job_postings_enriched
SELECT 
  j.job_id, j.job_title_short, j.salary_year_avg, 
  j.job_work_from_home, j.job_posted_date, j.job_location,
  CASE WHEN j.salary_year_avg > b.p50_salary THEN 'above_market' ELSE 'below_market' END as salary_position
FROM job_postings_fact j
LEFT JOIN salary_benchmarks_by_role b ON j.job_title_short = b.job_title_short;

-- Task 4: Aggregate by location (depends_on=['enrich_postings'])
INSERT INTO location_job_stats
SELECT 
  job_location,
  COUNT(*) as job_count,
  AVG(salary_year_avg) as avg_salary,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) as remote_job_count
FROM job_postings_enriched
GROUP BY job_location;
```

In Airflow DAG syntax: `load_raw >> load_benchmarks >> enrich >> aggregate`. If Task 3 fails, you retry only Task 3 without re-running Tasks 1–2.

## Notes

- **Mistake: implicit dependencies.** Hardcoding `sleep(600)` or table name assumptions creates brittle pipelines. Always declare dependencies explicitly in your orchestrator.
- **Mistake: over-eager fan-in.** If Task D depends on B, C, and E, but E is slow, all three are gated. Consider whether D truly needs all of them or if partial completion is acceptable.
- **Idempotency is DAG's partner.** A DAG ensures order, but idempotent tasks (insert-or-replace, upsert, dbt models with unique_id) make safe reruns possible without cascading deletes.
- **Watch for hidden dependencies.** Two tasks writing to the same table without explicit ordering create race conditions. Use the DAG to serialize writes or partition by key.
- **Connects to:** task retry logic, sensor patterns (waiting for external data), backfill and catchup in scheduled DAGs, and monitoring task SLA vs. actual runtime.

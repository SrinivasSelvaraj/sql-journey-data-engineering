---
date: 2026-08-22
phase: pipelines
topic: Fan-out and fan-in task patterns
---

# Fan-out and fan-in task patterns

*Pipelines and orchestration*

## Concept

Fan-out and fan-in are orchestration patterns that handle parallelization and synchronization in data pipelines. **Fan-out** splits one upstream task into many parallel downstream tasks (one-to-many); **fan-in** merges many parallel tasks into one (many-to-one). Together they enable efficient processing of large datasets by parallelizing independent work, then consolidating results before proceeding.

These patterns matter because data pipelines often have natural parallelism: processing data by region, by date partition, by customer segment. Without explicit fan-out, you serialize work that could run in parallel, wasting wall-clock time. Without fan-in, you create dependency hell—downstream tasks don't know when to start because they're waiting on an unknown number of upstream tasks.

Fan-out breaks when upstream task logic isn't idempotent or when you generate unbounded task lists (too many parallel tasks exhaust orchestrator capacity). Fan-in breaks when you have no defined collection point, causing hanging dependencies or silent failures if one of N parallel tasks fails.

## Practice

**Problem:** Load job postings data by region (10 regions), validate each region independently in parallel, then merge all validated datasets into a single deduplicated fact table.

```sql
-- Fan-out: Region-specific load & validation (run in parallel)
-- Task: load_and_validate_region_{region_name}
CREATE TABLE job_postings_region_{region_name}_validated AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date DESC) AS rn
FROM job_postings_fact
WHERE job_location LIKE '%{region_name}%'
  AND salary_year_avg > 0
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
QUALIFY rn = 1;

-- Fan-in: Merge all regions into final fact table (single downstream task)
-- Task: merge_all_regions (depends on all load_and_validate_region_* tasks)
CREATE OR REPLACE TABLE job_postings_fact_final AS
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM (
  SELECT * FROM job_postings_region_us_east_validated
  UNION ALL
  SELECT * FROM job_postings_region_us_west_validated
  UNION ALL
  SELECT * FROM job_postings_region_eu_validated
  -- ... repeat for all 10 regions
)
QUALIFY ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date DESC) = 1;
```

## Notes

- **Common mistake:** Creating unbounded fan-outs (e.g., one task per job_id instead of per region). Use bucketing, date ranges, or fixed categories to limit parallelism.
- **Failure propagation:** If one fanned-out task fails, the fan-in must fail loudly; use orchestrator sensors (Airflow `ExternalTaskSensor`, dbt `depends_on`) to enforce hard dependencies.
- **Idempotency requirement:** Fan-out tasks must be rerunnable without side effects; use truncate-then-insert or create temp tables, not appends.
- **Adjacent topics:** Connects to partitioning strategies (how to divide work), retry logic (failed fan-out tasks should trigger fan-in retry), and monitoring (track which parallel task caused fan-in failure).
- **Revisit:** Dynamic task mapping (Airflow 2.3+, dbt 1.5+) lets you generate fan-out task count at runtime based on query results rather than hardcoding region lists.

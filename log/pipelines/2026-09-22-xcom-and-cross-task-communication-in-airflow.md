---
date: 2026-09-22
phase: pipelines
topic: XCom and cross-task communication in Airflow
---

# XCom and cross-task communication in Airflow

*Pipelines and orchestration*

## Concept

XCom (cross-communication) is Airflow's mechanism for passing data between tasks within a DAG. Without it, every task is isolated—unable to access outputs from upstream work, forcing you to re-query databases or re-process files. This breaks the abstraction of a pipeline and creates redundant I/O.

When you need a task to act on a previous task's result—whether filtering based on a row count, routing logic based on a computed value, or passing filenames—XCom carries that payload. In Airflow 2.0+, XCom defaults to storing in the metadata database (serialized as JSON), making it lightweight for scalar values and small collections but inappropriate for large datasets (use external storage like S3 for that).

Without XCom, you lose visibility into intermediate state and force downstream tasks to recompute or guess. With it, you document task dependencies explicitly, enable conditional branching, and create auditable data lineage. A broken XCom pattern typically surfaces as tasks silently skipping, hardcoded values in DAG code, or redundant database queries.

## Practice

**Problem:** After loading job postings into `job_postings_fact`, you need to:
1. Count rows inserted in the load task
2. Send a warning alert if fewer than 100 rows were loaded
3. Only proceed to the aggregation task if the count exceeds 50

**Solution:**

```sql
-- Task 1: Load and push XCom
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT job_id, title, salary, remote_eligible, posted_at, location
FROM staging_jobs
WHERE posted_at >= CURRENT_DATE - INTERVAL '1 day';

-- Capture row count (Airflow operator wraps this and calls ti.xcom_push('row_count', count_value))
SELECT ROW_COUNT() AS row_count;
```

```python
# Task 2: Pull XCom and decide
def check_row_count(ti):
    count = ti.xcom_pull(task_ids='load_job_postings', key='row_count')
    if count < 100:
        send_alert(f"Only {count} rows loaded—below threshold")
    if count < 50:
        raise ValueError("Insufficient data; aborting aggregation")
    return count

# Task 3: Aggregation (conditional)
def aggregate_salaries(ti):
    count = ti.xcom_pull(task_ids='check_row_count')
    # proceed with aggregation knowing we have sufficient data
```

## Notes

- **Default serialization pitfall:** XCom serializes to JSON by default. Passing large DataFrames or binary objects silently fails or causes memory bloat—use external storage URIs (S3 paths, temp table names) instead.
- **Key naming discipline:** Always use explicit `key=` parameters (`ti.xcom_push('my_key', value)`) rather than default returns; it prevents collisions and clarifies intent.
- **Adjacent concern—task dependencies:** XCom creates *data* dependencies, not *scheduling* dependencies. Always set `>>` or `upstream_list` to ensure scheduler knows the order; XCom alone won't trigger tasks.
- **Debugging XCom:** Use the Airflow UI → task instance → XCom tab to inspect serialized values. Common surprises: None values, type coercion, timezone-naive datetimes.
- **Revisit for scale:** For production pipelines passing kilobytes+, migrate to artifact backends (S3, GCS) via XComArg and `@task.branch` for branching logic; this scales better than pushing to Postgres metadata DB.

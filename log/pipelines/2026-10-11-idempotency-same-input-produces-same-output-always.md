---
date: 2026-10-11
phase: pipelines
topic: Idempotency: same input produces same output always
---

# Idempotency: same input produces same output always

*Pipelines and orchestration*

## Concept

Idempotency means running the same operation multiple times with identical inputs always produces the same output and state—the second run changes nothing. In data pipelines, this is critical because failures happen: network timeouts, process crashes, scheduler retries. Without idempotency, retrying a failed job may duplicate data, overwrite partial results inconsistently, or leave the warehouse in an ambiguous state.

The stakes are highest in transformation and loading layers. If your pipeline increments a counter on retry instead of setting it, duplicates records instead of upserting, or appends to a table twice, downstream analytics break silently. Idempotency decouples *failure recovery* from *business logic*—you can retry freely without defensive coding everywhere.

Achieving idempotency often requires designing operations around upserts (insert-or-update), truncate-then-load patterns, or immutable inserts with deduplication. The cost is usually modest: a primary key, a unique constraint, or explicit DELETE before INSERT. The alternative—manual intervention, data reconciliation, or fear of retries—is far more expensive.

## Practice

**Problem:** A daily job loads job postings from an API into `job_postings_fact`. The API returns all postings from the last 7 days. If the job fails partway through and reruns the same day, some records will be inserted twice, inflating salary aggregates and job counts.

```sql
-- Idempotent solution: upsert pattern with merge or delete+insert
DELETE FROM job_postings_fact 
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';

INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
  job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM staging_api_load
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days';
```

Alternative using MERGE (Snowflake/SQL Server):
```sql
MERGE INTO job_postings_fact f
USING staging_api_load s
ON f.job_id = s.job_id AND f.job_posted_date = s.job_posted_date
WHEN MATCHED THEN UPDATE SET f.salary_year_avg = s.salary_year_avg, f.job_work_from_home = s.job_work_from_home
WHEN NOT MATCHED THEN INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
VALUES (s.job_id, s.job_title_short, s.salary_year_avg, s.job_work_from_home, s.job_posted_date, s.job_location);
```

## Notes

- **Unique constraints are not optional.** Define a natural key (job_id + job_posted_date, or API record ID) and enforce it. Without it, duplicates slip through silently and reconciliation is painful.
- **Truncate-and-reload only works with time-windowed loads.** If you load *all* historical data on every run, the pattern is safe; if you load only new data, use upsert instead to handle late arrivals and corrections.
- **Idempotency connects to observability and orchestration.** Idempotent jobs unlock confident automatic retries (Airflow, dbt, Dagster). Non-idempotent jobs require manual intervention and become pipeline bottlenecks.
- **Staging layers are your friend.** Load raw API/source data into a staging table first, then merge/upsert to the fact table. This separates data arrival from transformation and makes debugging easier.
- **Revisit: transaction isolation levels.** In high-concurrency environments, your idempotent DELETE+INSERT may race with concurrent reads. SERIALIZABLE isolation or explicit locking may be needed; understand the tradeoffs.

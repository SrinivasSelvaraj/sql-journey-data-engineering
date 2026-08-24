---
date: 2026-08-24
phase: cloud
topic: Spot and preemptible instances for batch workloads
---

# Spot and preemptible instances for batch workloads

*Cloud platforms and storage*

## Concept

Spot and preemptible instances are deeply discounted compute resources (60–90% cheaper) that cloud providers can reclaim with little or no notice. On GCP they're called preemptible VMs; on AWS they're spot instances. They're ideal for batch workloads—ETL jobs, data warehouse refreshes, model training—where interruption simply means the job restarts, not user-facing downtime.

The cost savings are enormous but come with a critical tradeoff: your job must be *idempotent* and *resumable*. If your transformation writes intermediate results to ephemeral storage and the instance disappears mid-job, you lose everything. If you checkpoint state to durable storage (object store, database) and code the retry logic, interruptions become mere delays, not failures.

Without understanding this, you'll either overpay for on-demand instances you don't need, or you'll experience mysterious batch job failures that seem random until you realize the instance was terminated. Combining spot instances with proper idempotency and monitoring is the practical way to optimize cloud costs at scale.

## Practice

**Problem:** Your data team runs a nightly job that aggregates job postings and calculates salary statistics by location. The job currently runs on on-demand instances at $2.50/hour; it takes 3 hours, so costs $7.50 per run, or $225/month. You want to reduce costs using preemptible instances but need the job to survive interruptions.

```sql
-- Solution: Use CTEs and upserts with checksums to ensure idempotency

-- 1. Source data with content hash (detect duplicates after restart)
WITH raw_postings AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_location,
    job_posted_date,
    MD5(CONCAT(job_id, salary_year_avg, job_location)) AS content_hash
  FROM source_raw_postings
  WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
),

-- 2. Aggregate at location level
location_stats AS (
  SELECT 
    job_location,
    COUNT(DISTINCT job_id) AS job_count,
    ROUND(AVG(salary_year_avg), 2) AS avg_salary,
    MAX(salary_year_avg) AS max_salary,
    MIN(salary_year_avg) AS min_salary,
    CURRENT_TIMESTAMP() AS computed_at,
    MD5(CONCAT(job_location, COUNT(*), ROUND(AVG(salary_year_avg), 2))) AS batch_hash
  FROM raw_postings
  WHERE salary_year_avg IS NOT NULL
  GROUP BY job_location
)

-- 3. Upsert into target table (idempotent: if job restarts, duplicates are replaced)
MERGE INTO job_postings_location_summary AS target
USING location_stats AS source
ON target.job_location = source.job_location
WHEN MATCHED AND target.batch_hash != source.batch_hash THEN
  UPDATE SET 
    job_count = source.job_count,
    avg_salary = source.avg_salary,
    max_salary = source.max_salary,
    min_salary = source.min_salary,
    computed_at = source.computed_at,
    batch_hash = source.batch_hash
WHEN NOT MATCHED THEN
  INSERT (job_location, job_count, avg_salary, max_salary, min_salary, computed_at, batch_hash)
  VALUES (source.job_location, source.job_count, source.avg_salary, source.max_salary, source.min_salary, source.computed_at, source.batch_hash);
```

**Expected outcome:** Job runs on preemptible instances ($0.25/hour ≈ $0.75/run, $22.50/month). If interrupted, the orchestrator (Airflow, Cloud Composer) retries; the MERGE ensures no duplicate aggregations. Cost reduction: 90%.

## Notes

- **Idempotency is non-negotiable.** Use MERGE/UPSERT with unique keys and checksums; avoid INSERT-only patterns. Without it, retries corrupt your data.
- **Pair with robust retry logic.** Set max retries (3–5) and exponential backoff in your orchestrator; preemptible instances fail ~2–5% of the time on average, but that's not random across all regions/times.
- **Monitor actual interruption rates.** Cloud providers publish metrics. If your job hits 30+ interruptions per month, the retry overhead negates savings; fall back to on-demand or committed discounts.
- **Distinguish from reserved/committed instances.** Spot/preemptible suit *variable* batch workloads; reserved instances suit baseline, predictable load. Many teams use both: reserved core + preemptible overflow.
- **Checkpoint state to cloud storage, not local disk.** Write intermediate results to GCS/S3, not the instance's ephemeral

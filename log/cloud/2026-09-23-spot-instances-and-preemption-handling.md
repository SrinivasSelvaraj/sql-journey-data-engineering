---
date: 2026-09-23
phase: cloud
topic: Spot instances and preemption handling
---

# Spot instances and preemption handling

*Cloud platforms and storage*

## Concept

Spot instances are cloud compute resources (VMs, containers) offered at steep discounts—often 70–90% cheaper than on-demand—because the cloud provider can reclaim them with minimal notice (typically 2–30 seconds) when capacity is needed elsewhere. They are ideal for fault-tolerant, interruptible workloads like batch ETL, model training, and data processing jobs, but dangerous for latency-sensitive or stateful operations without proper handling.

Preemption handling is the strategy you implement to survive these interruptions: checkpointing state, designing idempotent operations, retrying with backoff, and isolating work into small enough tasks that restarting is cheap. Without it, a 6-hour aggregation job can vanish mid-computation, forcing you to restart from scratch and wasting money. With it, you trade a small overhead for 70% cost savings and learn exactly which parts of your pipeline are resilient.

When does it matter most? When your data warehouse or lake processes terabytes nightly, when you're prototyping expensive transformations, or when your infra scales dynamically. A single-table lookup on-demand? Spot is overkill. A distributed Spark job partitioning 500GB of logs? Spot becomes non-optional for cost control. The key question: can your job be paused, checkpointed, and resumed without data loss or logic errors?

## Practice

**Problem:** You run a nightly job that denormalizes job postings into salary bands for dashboard queries. The job reads 5M rows, groups by location and title, computes percentiles, and writes results to a summary table. It currently runs on a single on-demand instance and costs $180/month. You want to run it on spot instances to save 75%, but the job must complete reliably by 8 AM for your stakeholders' reports.

```sql
-- Solution: Break the job into idempotent, checkpointed steps
-- Step 1: Ingest and stage raw data (idempotent upsert)
CREATE TABLE job_postings_staging AS
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_location,
  CURRENT_TIMESTAMP() AS load_ts
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
  AND salary_year_avg IS NOT NULL;

-- Step 2: Checkpoint: mark batch as ingested (allows resume)
CREATE TABLE IF NOT EXISTS batch_checkpoints (
  batch_id STRING,
  step_name STRING,
  status STRING, -- 'started', 'completed'
  run_ts TIMESTAMP
);

INSERT INTO batch_checkpoints VALUES 
  ('2024_01_22', 'ingest', 'completed', CURRENT_TIMESTAMP());

-- Step 3: Compute salary bands (only if prior step succeeded)
CREATE OR REPLACE TABLE salary_band_summary AS
SELECT 
  job_location,
  job_title_short,
  COUNT(*) AS posting_count,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary_year_avg) AS q1_salary,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY salary_year_avg) AS median_salary,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_year_avg) AS q3_salary
FROM job_postings_staging
WHERE load_ts >= (SELECT MAX(load_ts) FROM batch_checkpoints 
                   WHERE batch_id = '2024_01_22' AND status = 'completed')
GROUP BY job_location, job_title_short
HAVING COUNT(*) > 10;

-- Step 4: Mark aggregation complete
INSERT INTO batch_checkpoints VALUES 
  ('2024_01_22', 'aggregate', 'completed', CURRENT_TIMESTAMP());
```

## Notes

- **Idempotency is non-negotiable:** Use `CREATE OR REPLACE`, upserts with surrogate keys, or atomic writes. If your job reruns and duplicates data or logic, spot savings evaporate into debugging costs.
- **Checkpointing granularity matters:** Too coarse (whole job as one unit) means total restart on any failure. Too fine (every row) adds overhead. Aim for steps that take 5–15 minutes; a preemption loses only that window's work.
- **Adjacent topic—retry logic and exponential backoff:** Spot preemptions are random; on retry, request a different instance type or AZ. Cloud SDKs (Boto3, gcloud) provide spot request APIs that handle this; also pairs with circuit breaker patterns.
- **Cost optimization blind spot:** Spot *savings* hide if you ignore wall-clock latency. A job that takes 2 hours on spot (due to retries) but 30 min on-demand may cost more. Always log preemption frequency and retry overhead.
- **Testing: use chaos engineering.** Before running critical pipelines on spot, inject synthetic preemptions into your staging environment to confirm checkpoints work and your alerting fires correctly.

---
date: 2026-10-30
phase: cloud
topic: Spot instances and preemptible VM economics
---

# Spot instances and preemptible VM economics

*Cloud platforms and storage*

## Concept

Spot instances (AWS EC2) and preemptible VMs (Google Cloud) are spare cloud capacity sold at 60–90% discounts, but can be terminated with minutes of notice when demand spikes. They're ideal for fault-tolerant batch jobs—data pipelines, distributed training, bulk analytics—where interruption means restarting a task, not losing money. The economics are compelling: a 3-hour Spark job on spot instances might cost $2 instead of $20, but only if your workload can checkpoint or retry gracefully.

They matter acutely in data engineering because query costs and pipeline runtime are visible and measurable. A slow query on preemptible infrastructure isn't slow because the compute is weak; it's slow because tasks restart after interruption, adding latency and overhead. Without understanding interruption rates and retry logic, you'll blame infrastructure when the real problem is an unevenly distributed shuffle or missing task commit logic.

Breaking without them: cost-sensitive environments (startups, research teams, batch-heavy shops) lose 10–30% of total compute budget. Long-running, stateful queries without checkpointing become unreliable—a 6-hour aggregation that restarts halfway through wastes time and effort. Conversely, teams that ignore spot instances waste budget on premium on-demand capacity for work that doesn't require SLA guarantees.

## Practice

**Problem:** You're loading 5 years of job postings into a data warehouse weekly. The table has 2M rows. Your current on-demand cluster costs $500/month. You want to cut costs to $100/month using preemptible instances, but the load must complete reliably within 4 hours.

```sql
-- Solution: partition inserts with idempotent upserts + checkpointing
-- Step 1: Stage new data with deduplication (handles partial loads)
CREATE TEMP TABLE staged_jobs AS
SELECT DISTINCT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_TIMESTAMP() AS loaded_at
FROM external_source
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  AND job_id NOT IN (SELECT job_id FROM job_postings_fact);

-- Step 2: Load with idempotent merge (restarts safe)
MERGE INTO job_postings_fact AS target
USING staged_jobs AS source
ON target.job_id = source.job_id
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, source.job_work_from_home, source.job_posted_date, source.job_location)
WHEN MATCHED THEN
  UPDATE SET loaded_at = source.loaded_at;

-- Step 3: Log checkpoint for monitoring
INSERT INTO pipeline_log (pipeline_name, status, rows_loaded, run_date)
VALUES ('job_postings_weekly', 'SUCCESS', @@rowcount, CURRENT_DATE());
```

This approach tolerates 2–3 preemptions per load because the merge is idempotent—reruns don't duplicate rows.

## Notes

- **Idempotency is mandatory:** avoid `INSERT INTO` without deduplication logic; use `MERGE`, `INSERT … ON CONFLICT`, or external deduplication checks. One preemption on a raw insert breaks data quality.
- **Interruption rate varies by region, time-of-day, and instance family:** monitor actual termination rates for your workload; published 5% rates can be 15% during peak hours. Factor this into SLA calculations.
- **Spot pricing is volatile; on-demand pricing is stable:** suitable only for cost-optimized jobs, not revenue-critical queries. A $50/hour on-demand query interrupted by a $2 spot outage may waste more than it saves.
- **Connects to:** retry logic and exponential backoff (transient failures), task parallelization (coarse-grained tasks survive interruption better), and cost tagging (attributing infrastructure spend to job type).
- **Revisit when:** pipelines grow (costs compound); SLAs tighten (interruption tolerance shrinks); or workloads shift (long-running queries need different strategies than short bursts).

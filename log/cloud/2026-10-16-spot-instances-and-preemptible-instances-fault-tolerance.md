---
date: 2026-10-16
phase: cloud
topic: Spot instances and preemptible instances: fault tolerance
---

# Spot instances and preemptible instances: fault tolerance

*Cloud platforms and storage*

## Concept

Spot instances (AWS, GCP) and preemptible instances (GCP) are deeply discounted compute resources—often 70–90% cheaper than on-demand—that cloud providers can interrupt with minimal notice (seconds to minutes). They are ideal for fault-tolerant batch jobs where completion time is flexible, but catastrophic for long-running queries, interactive dashboards, or jobs with no checkpointing. The interruption is not a failure; it's a business model: you pay less because the provider reclaims idle capacity when demand spikes.

Without fault tolerance, a spot interruption mid-query wastes all work done so far and forces a restart from scratch, doubling effective cost and wall-clock time. With it—via retries, idempotent writes, or state checkpoints—you pay the discount price and tolerate restarts as a cost of doing business. This distinction is critical when cost-optimizing data pipelines: spot instances are a lever for jobs where you control retry logic and can afford delays; they are a trap for jobs that assume guaranteed uptime.

The cost savings are real only if your workload matches the fault-tolerance model. A 4-hour ETL job on spot instances that fails halfway and retries twice costs more in total compute time than running on-demand once.

## Practice

**Problem:** You run a nightly job that aggregates job postings by title and computes median salary. The aggregation takes 40 minutes on a spot instance, but interruptions cause it to restart frequently, extending nightly runtime to 3+ hours. You want to make this spot-friendly.

```sql
-- Unsafe: loses all progress on interruption
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as median_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 1 DAY
GROUP BY job_title_short;

-- Safe: idempotent staging table + atomic final swap
CREATE TABLE job_postings_agg_staging AS
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as median_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 1 DAY
GROUP BY job_title_short;

-- Only after full success: swap into production
ALTER TABLE job_postings_agg RENAME TO job_postings_agg_old;
ALTER TABLE job_postings_agg_staging RENAME TO job_postings_agg;
DROP TABLE job_postings_agg_old;
```

The staging table can be dropped and recreated on retry without affecting production; the rename is atomic.

## Notes

- **Confusing cost savings with actual savings:** A spot instance at $0.20/hour interrupted after 20 minutes is not cheaper than on-demand at $0.80/hour if the job must restart. Calculate expected wall-clock cost including retries.
- **Spot instances pair with container orchestration:** Kubernetes, Dataflow, and Spark handle retries and rescheduling. Raw EC2/GCE spot instances require you to build fault tolerance in application code.
- **Preemption ≠ failure:** Treat interruptions as normal, not exceptional. Logs should distinguish preemption (expected) from errors (bugs).
- **Checkpointing and idempotency are orthogonal:** Checkpointing resumes from a saved state (expensive to implement); idempotency (recompute from the start, write safely) is simpler for many batch jobs.
- **Reserved instances (commitment discounts) vs. spot:** Reserved instances guarantee uptime at 30–60% discount; spot is 70–90% but preemptible. Choose based on tolerance for interruption, not just price.

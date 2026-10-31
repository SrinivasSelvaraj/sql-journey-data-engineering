---
date: 2026-10-31
phase: cloud
topic: Spot price volatility and fault tolerance
---

# Spot price volatility and fault tolerance

*Cloud platforms and storage*

## Concept

Spot instances offer 60–90% cost savings but can be interrupted with minimal warning when cloud providers reclaim capacity. In data engineering, this volatility matters most for long-running batch jobs and interactive queries—a query that runs for 8 hours on a spot instance risks losing all progress if the instance terminates mid-execution. Fault tolerance means designing jobs to resume from checkpoints rather than restart from scratch, and understanding when to trade spot savings for on-demand stability (short ad-hoc queries can tolerate spot; mission-critical ETL pipelines usually cannot).

Without fault tolerance, you pay for wasted compute (the query runs again), lose SLA guarantees, and create unpredictability in cost reporting. More subtly, spot volatility makes query performance analysis unreliable—a slow query might be slow because of data volume or join strategy, or it might be slow because the instance was throttled before termination. Separating signal from noise requires either running on stable infrastructure or instrumenting jobs to detect and log terminations.

## Practice

**Problem:** A nightly job aggregates job postings by location and salary band, running at 2 a.m. You notice it sometimes completes in 12 minutes and sometimes in 45 minutes. Logs show no query changes. How would you add fault tolerance and cost monitoring?

```sql
-- Solution: Use staging table with idempotent insert pattern and cost tracking

-- 1. Create idempotent staging (drop and recreate, or use merge)
CREATE TABLE job_salary_by_location_staging AS
SELECT 
  job_location,
  CASE 
    WHEN salary_year_avg < 50000 THEN 'Entry'
    WHEN salary_year_avg < 100000 THEN 'Mid'
    ELSE 'Senior'
  END AS salary_band,
  COUNT(*) AS posting_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  CURRENT_TIMESTAMP AS load_ts
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY job_location, salary_band;

-- 2. Atomic swap: this prevents partial data
ALTER TABLE job_salary_by_location RENAME TO job_salary_by_location_old;
ALTER TABLE job_salary_by_location_staging RENAME TO job_salary_by_location;
DROP TABLE job_salary_by_location_old;

-- 3. Log runtime and instance metadata (run separately in wrapper script)
-- INSERT INTO job_run_log (job_name, start_time, end_time, instance_type, cost_estimate)
-- VALUES ('salary_by_location', ..., ..., 'spot', row_count * 0.00003);
```

The staging + swap pattern ensures either all data loads or none (no partial aggregates). Separately, log instance type and row count to calculate actual vs. expected costs, which reveals when spot terminations occurred.

## Notes

- **Common mistake:** Assuming query variability is algorithmic (poor join order) when it's actually infrastructure (spot termination or CPU throttling). Always log instance metadata and wall-clock time separately.
- **Checkpointing and restarts:** For very long jobs, write intermediate results to durable storage (e.g., checkpoint every 10M rows processed) so reruns resume from the last checkpoint, not from row 1.
- **Spot pools and diversity:** Use multiple spot instance types and availability zones in your cluster config; single-type spot pools have higher simultaneous termination risk.
- **Cost vs. reliability tradeoff:** On-demand costs 3–4× more but guarantees predictability. Reserve capacity for baseline load, spot for elastic bursts.
- **Related:** Query execution plans, SLAs and error budgets, infrastructure as code (IaC) for reproducible test environments, and observability (CloudWatch, Datadog) to correlate performance dips with spot events.

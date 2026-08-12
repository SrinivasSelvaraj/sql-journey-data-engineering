---
date: 2026-08-12
phase: pipelines
topic: Airflow: sensors, deferrable operators and pools
---

# Airflow: sensors, deferrable operators and pools

*Pipelines and orchestration*

## Concept

Sensors in Airflow are operators that wait for a condition to be true before proceeding—they're essential for handling dependencies external to your DAG, like "wait for a file to arrive" or "wait for an upstream system to finish." Without sensors, you either hardcode sleep times (fragile) or poll manually in your tasks (wasteful). Deferrable operators extend this: instead of blocking a worker thread while waiting, they suspend and resume when their condition is met, freeing that worker for other tasks. This matters enormously when you have many tasks waiting on I/O or external systems—blocking workers means wasted resources and constrained throughput.

Pools are Airflow's resource throttling mechanism. A pool sets a maximum number of task slots available for a group of tasks; when all slots are full, queued tasks wait. This prevents overwhelming downstream systems (e.g., don't run 50 API calls in parallel against a rate-limited endpoint) and enforces SLA guarantees. Without pools, a single DAG run can monopolize all workers or crash a fragile dependency. Sensors, deferrable operators, and pools work together: sensors and deferrable operators reduce blocking, while pools ensure you don't overwhelm external systems even when scaled horizontally.

## Practice

**Problem:** You're loading job postings data from an API that publishes a daily summary file to S3 at an unpredictable time between midnight and 6am. You have 20 downstream tasks that transform this data, but only 5 should run in parallel to stay within the API's rate limit for enrichment calls. Design a DAG structure that waits for the file without blocking workers, then throttles the enrichment tasks.

```sql
-- After the file arrives and is loaded, aggregate job posting stats to validate the load
SELECT 
  DATE(job_posted_date) as posting_date,
  COUNT(*) as total_postings,
  COUNT(DISTINCT job_id) as unique_jobs,
  ROUND(AVG(salary_year_avg), 2) as avg_salary,
  ROUND(SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) as pct_remote
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE - INTERVAL '1 day'
GROUP BY DATE(job_posted_date);
```

*DAG design:* Use `S3KeySensor(bucket, key, mode='poke')` with `poke_interval=300` (5 min) to wait for the file. Set `deferrable=True` and use a deferrable S3 sensor if available (Airflow 2.2+). Add all 20 enrichment tasks to a pool named `api_enrichment_pool` with `pool_slots=5`. The sensor doesn't block; the pool queues enrichment tasks, releasing 5 at a time.

## Notes

- **Common mistake:** Using blocking sensors (mode='poke') on short intervals in a DAG with many tasks—this starves the scheduler. Default to `deferrable=True` or use `mode='reschedule'` to minimize worker waste.
- **Pool confusion:** Pools are *per task*, not per DAG. Set `pool='my_pool'` and `pool_slots=1` (or more) on individual tasks; don't confuse with `max_active_tasks_per_dag`.
- **Sensor timeout logic:** Always set `timeout` and `poke_interval` thoughtfully. A 30-second poke_interval over 8 hours = 960 pokes; use exponential backoff or longer intervals for overnight waits.
- **Adjacent topics:** Backfill behavior with sensors (backfill will re-trigger sensor waits), deadletter/retry patterns (sensor failures vs. task failures are different), and trigger rules (how to handle sensor timeouts in downstream logic).
- **Revisit:** Dynamic task mapping pairs well with pools—map a single enrichment task across 20 job IDs with `pool_slots=5` for automatic fan-out control without hardcoding 20 tasks.

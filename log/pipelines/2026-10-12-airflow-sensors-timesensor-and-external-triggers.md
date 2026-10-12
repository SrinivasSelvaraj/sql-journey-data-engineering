---
date: 2026-10-12
phase: pipelines
topic: Airflow sensors: TimeSensor and external triggers
---

# Airflow sensors: TimeSensor and external triggers

*Pipelines and orchestration*

## Concept

**TimeSensor** pauses a DAG until a specific wall-clock time arrives, useful for scheduling tasks after business hours or waiting for external systems to be ready at predictable times. It's a passive sensor—it doesn't check for data or conditions, only the clock. **External triggers** (sensors like ExternalTaskSensor, FileSensor, or custom sensors) actively probe for the presence of upstream work, files, or API signals before proceeding. Together they solve the orchestration problem of "run when ready" vs. "run at this time."

Without them, you either hardcode fixed delays (wasteful, brittle) or poll manually in Python code (couples business logic to infrastructure). TimeSensor prevents mid-pipeline failure from clock skew; external triggers prevent cascading failures when dependencies aren't met. Missing the right sensor choice leads to either stuck DAGs waiting on nothing, or tasks hammering external APIs while pretending to be idempotent.

Choosing between them matters for cost and clarity: TimeSensor is cheap but only works for deterministic schedules; external sensors are heavier but self-documenting and safer for data-dependent workflows.

## Practice

**Problem:** Your job_postings ETL runs nightly at 2 AM. Raw job data lands in S3 at 2:15 AM from a partner API (variable), and salary enrichment data arrives in a separate bucket at 2:30 AM. You need the transformation task to wait for *both* files before proceeding, but not start earlier than 2 AM.

**Solution:**

```sql
-- DAG logic (pseudocode representation):
-- wait_for_2am = TimeSensor(target_time='02:00')
-- wait_for_postings_file = FileSensor(
--     filepath='/data/job_postings_raw/*.parquet',
--     poke_interval=30  -- check every 30 seconds
-- )
-- wait_for_salary_file = FileSensor(
--     filepath='/data/salary_enrichment/*.parquet',
--     poke_interval=30
-- )
-- 
-- transform = BashOperator(
--     bash_command='''
--     SELECT 
--       jp.job_id,
--       jp.job_title_short,
--       COALESCE(se.salary_year_avg, jp.salary_year_avg) AS salary_year_avg,
--       jp.job_work_from_home,
--       jp.job_posted_date,
--       jp.job_location
--     FROM job_postings_fact jp
--     LEFT JOIN salary_enrichment se ON jp.job_id = se.job_id
--     WHERE jp.job_posted_date = CURRENT_DATE
--     '''
-- )
--
-- [wait_for_2am, wait_for_postings_file, wait_for_salary_file] >> transform

-- In production: wrap in try-except with exponential backoff in sensor poke_interval
-- Set timeout=600 on FileSensor to fail loudly after 10 minutes
```

## Notes

- **TimeSensor gotcha:** It's timezone-aware but defaults to UTC; always set `timezone` parameter explicitly to match your data warehouse or business hours.
- **FileSensor fragility:** Checks for file *existence*, not completeness—pair with a `.done` marker file or atomic write pattern to avoid partial reads.
- **Sensor timeout vs. poke:** Long `poke_interval` saves resources but delays detection; short intervals risk overwhelming the scheduler. Balance per SLA (30–60s is typical for data pipelines).
- **Related pattern:** SLA miss alerts; sensors should fail **loudly** (not silently retry forever) so on-call notices data doesn't arrive. Use `mode='poke'` (blocking) for critical paths, `mode='reschedule'` (slot-freeing) for non-blocking waits.
- **Testing gotcha:** Mock sensors in unit tests or use `execution_timeout` to prevent local test hangs; never leave sensors unbound in development DAGs.

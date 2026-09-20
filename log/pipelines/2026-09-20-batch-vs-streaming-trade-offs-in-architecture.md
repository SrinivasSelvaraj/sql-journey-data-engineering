---
date: 2026-09-20
phase: pipelines
topic: Batch vs streaming trade-offs in architecture
---

# Batch vs streaming trade-offs in architecture

*Pipelines and orchestration*

## Concept

Batch processing runs jobs on a fixed schedule (hourly, daily) and processes accumulated data in bulk; streaming processes data continuously as it arrives. Batch is simpler to orchestrate, debug, and rerun—you have clear input boundaries and can easily replay failed intervals. Streaming offers lower latency but requires idempotent operations, careful state management, and monitoring for backpressure. The choice trades operational complexity against freshness requirements.

In pipelines, this matters because batch jobs fail loudly (you see the entire run succeed or fail) and rerun safely (replay the time window); streaming jobs can silently lag, lose state on restart, or duplicate records if you're not rigorous about deduplication and checkpointing. Most data warehouses prefer batch because it aligns with scheduled reporting and makes data lineage transparent—you know exactly which records were processed when.

Without explicit trade-off thinking, you end up building pseudo-streaming solutions (micro-batches every 5 minutes) that have neither batch's clarity nor streaming's true latency, or you over-engineer batch jobs with unnecessary complexity. Know your SLA: if reports refresh daily, batch wins; if alerts must fire within seconds, streaming is mandatory.

## Practice

**Problem:** Job postings arrive throughout the day. Your stakeholder wants daily salary insights by 9 AM, but the raw feed can have duplicates and late-arriving records up to 2 hours after posting. Design a batch pipeline that handles both requirements safely.

```sql
-- Batch job: runs daily at 9 AM, processes all postings from yesterday
-- Assumes late arrivals (up to 2 hours) are included in the "previous day" logic

WITH raw_postings AS (
  -- Capture all postings from yesterday, including 2-hour late window
  SELECT *
  FROM job_postings_raw
  WHERE DATE(job_posted_date) >= CURRENT_DATE - INTERVAL 1 DAY
    AND DATE(job_posted_date) < CURRENT_DATE
),
deduplicated AS (
  -- Dedup by job_id, keeping latest version by posted_date
  SELECT DISTINCT ON (job_id)
    job_id, job_title_short, salary_year_avg, 
    job_work_from_home, job_posted_date, job_location
  FROM raw_postings
  ORDER BY job_id, job_posted_date DESC
)
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, 
                               job_work_from_home, job_posted_date, job_location)
SELECT * FROM deduplicated
ON CONFLICT (job_id) DO UPDATE SET
  salary_year_avg = EXCLUDED.salary_year_avg,
  job_posted_date = EXCLUDED.job_posted_date;

-- Audit: log run metadata for replay capability
INSERT INTO pipeline_runs (table_name, run_date, record_count, status)
SELECT 'job_postings_fact', CURRENT_DATE, COUNT(*), 'SUCCESS'
FROM deduplicated;
```

## Notes

- **Common mistake:** Running batch jobs too frequently (hourly) trying to approximate streaming—this increases orchestration burden and makes debugging stateful failures harder. Stick to your actual SLA window.
- **Idempotency is non-negotiable:** Use `ON CONFLICT` or merge logic so reruns don't double-load data. Batch safety depends on this.
- **Adjacent: watermarking and late data.** Define explicit cutoff windows (job_posted_date boundaries) and handle late arrivals explicitly rather than hoping they appear on the next run.
- **Adjacent: orchestration tooling.** Airflow, dbt, Prefect all make batch lineage visible; invest in audit tables (pipeline_runs) so you can replay specific date ranges without guessing.
- **Revisit when:** Your batch window no longer fits your SLA (reports needed within 1 hour of data arrival) or you're managing hundreds of interdependent jobs (then consider streaming subcomponents for fast paths, batch for the rest).

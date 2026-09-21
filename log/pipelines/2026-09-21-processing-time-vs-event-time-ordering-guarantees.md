---
date: 2026-09-21
phase: pipelines
topic: Processing time vs event time ordering guarantees
---

# Processing time vs event time ordering guarantees

*Pipelines and orchestration*

## Concept

Processing time is when a record enters your system; event time is when the event actually occurred. These rarely align. A user click happens at 2pm, but your log collector batches and sends it at 2:47pm. Without explicit ordering guarantees, your aggregations will be wrong—revenue attributed to the wrong day, late-arriving facts silently overwriting correct ones, or duplicate-key inserts failing mid-pipeline.

Event time ordering matters most in dimensional tables and fact tables with slowly changing dimensions (SCD). If a job posting's salary is corrected three days after posting, but your pipeline processes the correction before the original record, you'll compute metrics on stale data. Your pipeline must either enforce arrival order via explicit timestamps, or allow late updates with proper SCD logic and idempotent writes.

Without ordering guarantees, your pipeline's behavior becomes non-deterministic. Rerunning the same historical batch may produce different results depending on the order records surface from your source. This violates the "rerun safely" principle—a fundamental requirement for trustworthy data engineering.

## Practice

**Problem:** You load job postings daily. A posting created on 2024-01-15 arrives in your 2024-01-16 batch (one day late). Meanwhile, a salary correction for that same posting—timestamped 2024-01-17—arrives in the 2024-01-16 batch. Without handling event time order, your incremental load logic may process the correction before the original record, leaving the original record missing entirely.

```sql
-- Solution: Use event-time-ordered staging with deduplication and SCD Type 2

INSERT INTO job_postings_fact
WITH ordered_events AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,  -- event time, not processing time
    job_location,
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date ASC, _loaded_at ASC) as rn
  FROM staging_job_postings
  WHERE _loaded_at >= CURRENT_DATE - 2  -- reprocess last 2 days to catch late arrivals
)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_TIMESTAMP as dbt_load_dts
FROM ordered_events
WHERE rn = 1  -- keep only first occurrence per job_id (earliest event time)
ON CONFLICT (job_id) DO UPDATE SET
  salary_year_avg = EXCLUDED.salary_year_avg,
  job_work_from_home = EXCLUDED.job_work_from_home,
  dbt_load_dts = CURRENT_TIMESTAMP
WHERE job_postings_fact.job_posted_date <= EXCLUDED.job_posted_date;  -- only update if new record is from same or later event time
```

## Notes

- **Don't confuse `_loaded_at` with business logic timestamps.** Use `job_posted_date` for deduplication and aggregations, not the timestamp your collector recorded. Processing time is metadata for debugging late arrivals, not for facts.
- **Idempotency requires both event-time ordering AND conflict resolution.** `ON CONFLICT DO UPDATE` alone isn't enough if records arrive out of order; add a `WHERE` clause comparing event timestamps to reject stale updates.
- **Slowly Changing Dimensions (SCD Type 2) solve some ordering problems.** If you can't guarantee order, add `valid_from` and `valid_to` columns and insert new rows instead of updating. Trade storage for correctness.
- **Rewindow your reprocessing window during backfills.** Set `_loaded_at >= CURRENT_DATE - 7` or wider when replaying historical data to catch delayed records; narrow it back down for daily runs once stable.
- **Connect this to idempotent retries.** A failed job that reruns must process the same event-time slice and produce identical results. Partitioning by event date, not load date, enables this.

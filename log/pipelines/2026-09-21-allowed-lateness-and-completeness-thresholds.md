---
date: 2026-09-21
phase: pipelines
topic: Allowed lateness and completeness thresholds
---

# Allowed lateness and completeness thresholds

*Pipelines and orchestration*

## Concept

Allowed lateness and completeness thresholds define how you handle incomplete or delayed data in pipelines. Allowed lateness specifies how long after the event time you'll accept data (e.g., "accept records up to 2 hours late"), while completeness thresholds set minimum data quality gates (e.g., "fail the pipeline if fewer than 95% of expected records arrive"). Together they prevent two failure modes: silently processing incomplete datasets that skew analytics, or waiting indefinitely for stragglers and blocking downstream consumers.

Without these boundaries, pipelines either proceed on phantom data (missing 30% of daily job postings but running anyway) or become brittle dependencies that fail mysteriously when external sources delay by unpredictable amounts. They're essential for streaming and near-real-time batch work where "eventual consistency" is intentional, not accidental.

Define thresholds based on SLA commitments to downstream teams, not wishful thinking. A hiring dashboard needs near-complete data daily; an ML feature store can tolerate 2–3 hour delays if it improves data quality.

## Practice

**Problem:** Your `job_postings_fact` table receives late-arriving records from job boards (some post corrections hours later). You want to ingest daily snapshots but need to know if you're missing data, and you want to allow corrections to flow in for up to 6 hours after the job_posted_date.

```sql
-- Check completeness and enforce late-arrival policy
WITH daily_snapshot AS (
  SELECT
    job_posted_date,
    COUNT(*) as record_count,
    COUNT(DISTINCT job_id) as unique_jobs,
    CURRENT_TIMESTAMP() as loaded_at
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE() - INTERVAL '1 day'
    AND CURRENT_TIMESTAMP() <= (job_posted_date + INTERVAL '6 hours')
  GROUP BY job_posted_date
),
completeness_check AS (
  SELECT
    job_posted_date,
    record_count,
    unique_jobs,
    loaded_at,
    CASE 
      WHEN unique_jobs >= 1000 THEN 'PASS'
      WHEN unique_jobs >= 500 THEN 'WARN'
      ELSE 'FAIL'
    END as completeness_status
  FROM daily_snapshot
)
SELECT * FROM completeness_check
WHERE completeness_status = 'FAIL'
  THEN RAISE_ERROR(
    FORMAT('Completeness threshold failed: %d jobs loaded, minimum 500 required',
      unique_jobs)
  );
```

## Notes

- **Confusing lateness with SLA:** Allowed lateness is about *when you accept data*, not *when you promise results to users*. Set lateness windows based on source reliability, not downstream demands.
- **Static thresholds fail:** Completeness needs context—job postings vary seasonally and by day-of-week. Use rolling baselines (95% of last 7 days' median) instead of fixed counts.
- **Connects to:** dead-letter queues (where late/malformed data lives), watermarking in streaming systems, and alert fatigue (too-strict thresholds trigger false positives).
- **Common mistake:** Allowing lateness but not logging it. Track late-arrived records separately so you can prove data quality to stakeholders and tune thresholds over time.
- **Worth revisiting:** How to handle corrections that arrive *after* your late-arrival window closes—you'll need a backfill or upsert strategy beyond the initial ingest.

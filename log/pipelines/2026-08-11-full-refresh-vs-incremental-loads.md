---
date: 2026-08-11
phase: pipelines
topic: Full refresh vs incremental loads
---

# Full refresh vs incremental loads

*Pipelines and orchestration*

## Concept

A **full refresh** rebuilds an entire table from source data each run; an **incremental load** processes only new or changed records since the last run. Full refreshes are simpler to reason about (idempotent, no state tracking) but expensive at scale; incremental loads are efficient but require careful handling of late-arriving data, deduplication, and resumability after failure.

The choice matters because it determines pipeline cost, latency, and failure modes. A full refresh on a 500M-row table running every hour wastes compute and storage churn. An incremental load that loses track of what was processed crashes into duplicates and data loss. Without explicit strategy, you either overpay or silently corrupt data.

Picking the wrong approach breaks reproducibility: if your incremental load restarts mid-batch, do you reprocess the same records? If a full refresh fails halfway, do you leave a half-built table live? These questions demand explicit design—checkpoint markers, atomic swaps, idempotent merges, or watermark tracking.

## Practice

**Problem:** Your `job_postings_fact` table is loaded daily from an API. The source has 2M new postings per day but 10% are corrections (same `job_id`, posted yesterday, updated today). A full refresh takes 45 minutes and strains your warehouse. Design an incremental load that handles corrections without duplicates.

```sql
-- Incremental load with upsert pattern
WITH source_data AS (
  SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, 
         job_posted_date, job_location, CURRENT_TIMESTAMP as load_ts
  FROM external_api_extract
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '2 days'  -- 2-day lookback for corrections
),
deduped AS (
  SELECT * 
  FROM source_data
  QUALIFY ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY load_ts DESC) = 1
)
MERGE INTO job_postings_fact AS target
USING deduped AS source
ON target.job_id = source.job_id
WHEN MATCHED THEN
  UPDATE SET job_title_short = source.job_title_short,
             salary_year_avg = source.salary_year_avg,
             job_work_from_home = source.job_work_from_home,
             job_location = source.job_location
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, 
          source.job_work_from_home, source.job_posted_date, source.job_location);
```

## Notes

- **Watermark trap:** Tracking "last processed timestamp" is fragile if source data arrives out of order. Always add a 1–2 day lookback window and deduplicate by natural key.
- **Idempotency requirement:** Incremental loads must be safe to rerun. MERGE/UPSERT patterns are safer than DELETE+INSERT because they're atomic; avoid multi-statement transactions that can partially fail.
- **Full refresh as fallback:** Even with incremental loads, schedule a weekly full refresh as a safety valve to catch corruption or missed records. It buys you insurance.
- **State management:** Track checkpoints (last job_id processed, max timestamp seen) in a separate metadata table, not in comments. On failure, your orchestrator should query this to resume, not guess.
- **Adjacent:** Connects to slowly changing dimensions (SCD Type 2), exactly-once semantics, and idempotency contracts in orchestrators like Airflow and dbt.

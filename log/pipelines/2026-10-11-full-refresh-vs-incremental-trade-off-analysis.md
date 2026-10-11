---
date: 2026-10-11
phase: pipelines
topic: Full refresh vs incremental: trade-off analysis
---

# Full refresh vs incremental: trade-off analysis

*Pipelines and orchestration*

## Concept

A **full refresh** rebuilds the entire target table from source data every run; an **incremental load** processes only new or changed records since the last successful run. Full refresh is simpler—no state tracking, no late-arriving data logic—but becomes expensive at scale: scanning millions of rows daily when only hundreds changed wastes compute and storage I/O. Incremental is faster and cheaper but demands a mechanism to detect what changed (timestamps, sequence numbers, CDC logs) and a way to recover when that mechanism fails.

The trade-off surfaces under real constraints: full refresh on a 500M-row table takes 2 hours and locks resources; incremental on the same table takes 3 minutes but requires a reliable `updated_at` column and idempotent writes. Without choosing deliberately, you either overspend on compute or lose data consistency when late-arriving records appear after the cutoff window.

This matters most when orchestration must be predictable. A pipeline that always runs in 90 seconds is easier to schedule, alert on, and reason about than one that sometimes takes 10 minutes. Incremental designs must fail loud (alert if no rows changed when 1000 were expected) and rerun safely (idempotent inserts or merge logic that handles duplicates).

## Practice

**Problem:** The `job_postings_fact` table grows by ~5,000 rows daily. A full refresh currently scans 2M historical rows to update 100 new postings and takes 45 minutes. Design an incremental solution that reprocesses only new data, handles late arrivals (postings with backdated `job_posted_date`), and fails if fewer than 100 rows are detected in a run.

```sql
-- Incremental load with late-arrival handling
-- Step 1: Track last successful load
CREATE TABLE IF NOT EXISTS pipeline_state (
  table_name VARCHAR,
  last_cutoff_date DATE,
  row_count_loaded INT,
  run_timestamp TIMESTAMP,
  PRIMARY KEY (table_name)
);

-- Step 2: Load only records newer than the last cutoff, plus a 7-day lookback for late arrivals
WITH new_data AS (
  SELECT * FROM job_postings_staging
  WHERE job_posted_date >= (
    SELECT COALESCE(last_cutoff_date - INTERVAL 7 DAY, '2020-01-01')
    FROM pipeline_state WHERE table_name = 'job_postings_fact'
  )
),
-- Step 3: Merge into fact table (upsert by job_id)
upserted AS (
  MERGE INTO job_postings_fact f
  USING new_data n
  ON f.job_id = n.job_id
  WHEN MATCHED THEN UPDATE SET
    job_title_short = n.job_title_short,
    salary_year_avg = n.salary_year_avg,
    job_work_from_home = n.job_work_from_home,
    job_posted_date = n.job_posted_date,
    job_location = n.job_location
  WHEN NOT MATCHED THEN INSERT *
)

-- Step 4: Validate row count and update state
SELECT 
  CASE 
    WHEN row_count < 100 THEN ERROR('Expected ≥100 rows; got ' || row_count)
    ELSE 'OK'
  END AS validation,
  row_count
FROM (
  SELECT ROW_COUNT() as row_count
) v;

UPDATE pipeline_state
SET last_cutoff_date = CURRENT_DATE,
    row_count_loaded = (SELECT COUNT(*) FROM new_data),
    run_timestamp = CURRENT_TIMESTAMP
WHERE table_name = 'job_postings_fact';
```

## Notes

- **State management is critical:** Without tracking `last_cutoff_date`, you either re-process the world or skip records. Version your pipeline state table; corruption here breaks everything downstream.

- **The 7-day lookback window:** Job postings with backdated `job_posted_date` values arrive late. A pure watermark strategy (load only records posted after yesterday) misses them. Always add a small overlap window; merge logic handles duplicates safely.

- **Fail loud on expectations:** The `ERROR()` call above is not optional—silent underruns (expecting 5K, getting 50) are data quality timebombs. Wire row-count assertions into every incremental pipeline.

- **Idempotency is non-negotiable:** Use `MERGE` or `INSERT ... ON CONFLICT UPDATE` rather than `DELETE + INSERT`, which leaves a window where queries see no data. Orchestrators will rerun failed tasks; your pipeline must survive that without data loss.

- **Revisit: CDC (Change Data Capture)** for high-velocity sources, **partition pruning** to make full refresh feasible on time-bounded subsets, and **data freshness SLAs** to decide when incremental complexity is justified vs. full refresh simplicity.

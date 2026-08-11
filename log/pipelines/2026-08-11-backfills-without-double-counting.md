---
date: 2026-08-11
phase: pipelines
topic: Backfills without double counting
---

# Backfills without double counting

*Pipelines and orchestration*

## Concept

A backfill reprocesses historical data to recalculate metrics, fix bugs, or apply new transformations. Double counting occurs when backfilled rows merge with production rows without deduplication, inflating aggregates and breaking downstream contracts. This is especially dangerous in append-only pipelines and fact tables where late-arriving or corrected records can silently corrupt months of analytics.

The risk intensifies when backfills overlap with active production loads. If you reprocess January data on day 31 while daily jobs already loaded January 1–30, you'll see duplicate metrics unless your pipeline explicitly handles idempotency. Teams often discover this days later during reconciliation, making the cost of backfill mistakes compounding.

Preventing double counting requires three things: (1) a **grain-level deduplication key** that uniquely identifies each logical record, (2) explicit **backfill date ranges** that don't overlap with future production, and (3) **sink idempotency**—either upserting on the grain key or deleting-then-inserting the backfill window before reloading.

## Practice

**Problem:** You're backfilling `job_postings_fact` to add a new column `job_industry`. A previous load inserted rows for 2024-01-01 to 2024-01-15. Your backfill logic recalculates the entire January 2024 window. Without deduplication, January 1–15 rows will appear twice in aggregates, inflating job counts.

```sql
-- Safe backfill: delete the window, then insert fresh
DELETE FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01' 
  AND job_posted_date < '2024-02-01';

INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, job_industry)
SELECT 
  jd.job_id,
  jd.job_title_short,
  jd.salary_year_avg,
  jd.job_work_from_home,
  jd.job_posted_date,
  jd.job_location,
  il.industry  -- newly joined lookup
FROM raw_job_data jd
LEFT JOIN industry_lookup il ON jd.job_category = il.category
WHERE jd.job_posted_date >= '2024-01-01' 
  AND jd.job_posted_date < '2024-02-01';
```

## Notes

- **Grain confusion**: Identify your fact table's grain (e.g., one row per job posting). Backfills without a clear grain key often produce duplicates at subtly different cardinalities (job_id vs. job_id + posting_timestamp).
- **Upsert vs. delete-insert**: Upserts (merge/insert on conflict) work well for slowly changing dimensions but are risky for facts. Delete-then-insert is safer and more debuggable for backfills; always specify the exact date window in both clauses.
- **Overlapping windows**: If production runs daily 2024-01-02 onwards and you backfill 2024-01-01 to 2024-01-31 on 2024-02-05, ensure the delete window covers *exactly* the backfill range, not beyond.
- **Related to idempotency and replayability**: This connects to partition pruning (backfill only what changed), lineage tracking (which records came from which load), and orchestration safety (DAGs that safely retry without manual intervention).
- **Test in dev first**: Always dry-run backfill logic on a small date range with counts before/after to catch cardinality shifts. Log row counts at each step.

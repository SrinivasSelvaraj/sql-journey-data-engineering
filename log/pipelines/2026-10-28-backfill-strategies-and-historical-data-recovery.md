---
date: 2026-10-28
phase: pipelines
topic: Backfill strategies and historical data recovery
---

# Backfill strategies and historical data recovery

*Pipelines and orchestration*

## Concept

Backfill is the process of recomputing historical data in a pipeline after a code change, bug fix, or schema update. Without it, your analytics layer reflects only the truth *from the moment the fix shipped*, creating a discontinuity that breaks trend analysis and comparisons. This matters most when you discover a calculation error weeks after it entered production—you can't just fix the code and hope; you must reprocess the affected date range so historical records match current logic.

A robust backfill strategy prevents data inconsistency and enables safe reruns. It answers: Can I rerun a job for dates 2024-01-01 through 2024-03-31 without duplicating or losing records? What happens if the job fails halfway through? The answer determines whether you trust your month-over-month metrics. Without explicit backfill handling, you either leave broken history in place (undermine trust) or manually delete and recompute (fragile, error-prone).

## Practice

**Problem:** You discover that `salary_year_avg` was being calculated incorrectly for remote jobs—it was missing a 12% adjustment. The bug ran for three months (2024-01-01 to 2024-03-31). You need to safely recalculate those records without duplicating non-remote rows or breaking downstream reports.

```sql
-- 1. Identify the backfill window
WITH backfill_window AS (
  SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
  FROM job_postings_fact
  WHERE job_posted_date BETWEEN '2024-01-01' AND '2024-03-31'
    AND job_work_from_home = TRUE
),
-- 2. Recalculate with corrected logic
corrected_salaries AS (
  SELECT 
    job_id,
    job_title_short,
    ROUND(salary_year_avg * 1.12) AS salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location
  FROM backfill_window
),
-- 3. Merge: delete old rows, insert corrected ones (idempotent via job_id uniqueness)
-- In practice, use MERGE or DELETE + INSERT in a transaction
DELETE FROM job_postings_fact
WHERE job_id IN (SELECT job_id FROM corrected_salaries);

INSERT INTO job_postings_fact
SELECT * FROM corrected_salaries;
```

## Notes

- **Idempotency is non-negotiable:** Backfill jobs must be safe to run twice. Use `DELETE WHERE date_range` before `INSERT`, or use `MERGE` / `UPSERT` on a unique key. Never append blindly.
- **Window boundaries matter:** Clearly document which dates are affected. Off-by-one errors (inclusive vs. exclusive end dates) silently corrupt history.
- **Coordinate with downstream:** Backfills invalidate dependent views and aggregates. Plan invalidation and re-materialization; communicate with analytics teams so they know metrics will refresh.
- **Log every backfill:** Record *why* (bug ticket), *what* (date range, row count), and *when* in a backfill audit table. This builds confidence in historical data and speeds future debugging.
- **Test on a sample first:** Run the backfill logic on a small date slice in dev/staging before committing to production. Verify counts, spot-check values, and confirm downstream impact.

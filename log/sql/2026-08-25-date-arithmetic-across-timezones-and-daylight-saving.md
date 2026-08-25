---
date: 2026-08-25
phase: sql
topic: Date arithmetic across timezones and daylight saving
---

# Date arithmetic across timezones and daylight saving

*SQL for analytics and engineering*

## Concept

Date arithmetic across timezones and daylight saving time is essential when working with events that span geographic regions or when reconciling timestamps from distributed systems. Without explicit timezone handling, you may incorrectly aggregate events (counting the same hour twice during a "fall back" transition, or missing an hour during "spring forward"), misalign job posting windows across regions, or produce off-by-one errors in cohort analysis. Most SQL engines store timestamps in UTC internally but display them in session timezone—the mismatch becomes dangerous when you extract date components, calculate day-of-week boundaries, or join on date ranges without normalizing first. The core issue: `DATE(timestamp_column)` applied to a timestamp in a session timezone will give different results than `DATE(CONVERT_TZ(timestamp_column, 'source_tz', 'UTC'))` before extraction, especially near DST transitions.

## Practice

**Problem:** You have job postings stored as `job_posted_date` (DATE type) created in US/Eastern timezone. Your analytics dashboard runs in UTC. You need to count how many jobs were posted each day in Eastern time, but also flag any days where DST transition occurred (where the day had 23 or 25 hours). Write a query that:
1. Groups postings by the actual Eastern-time date
2. Calculates the number of hours in that Eastern date
3. Filters to show only anomalous DST days

```sql
WITH postings_eastern AS (
  SELECT
    job_id,
    job_posted_date,
    -- Convert UTC to Eastern; handles DST automatically
    CONVERT_TZ(CONCAT(job_posted_date, ' 00:00:00'), 'UTC', 'US/Eastern') AS eastern_start,
    CONVERT_TZ(CONCAT(DATE_ADD(job_posted_date, INTERVAL 1 DAY), ' 00:00:00'), 'UTC', 'US/Eastern') AS eastern_end
  FROM job_postings_fact
)
SELECT
  job_posted_date,
  COUNT(*) AS posting_count,
  TIMESTAMPDIFF(HOUR, eastern_start, eastern_end) AS hours_in_day,
  CASE 
    WHEN TIMESTAMPDIFF(HOUR, eastern_start, eastern_end) <> 24 THEN 'DST_TRANSITION'
    ELSE 'NORMAL'
  END AS day_type
FROM postings_eastern
GROUP BY job_posted_date, eastern_start, eastern_end
HAVING TIMESTAMPDIFF(HOUR, eastern_start, eastern_end) <> 24
ORDER BY job_posted_date;
```

## Notes

- **Preserve intent vs. storage:** If `job_posted_date` is already a DATE (no time component), you lose the original timestamp. Always ask: was this event recorded in source timezone or UTC? Store the answer in metadata or column naming (e.g., `job_posted_ts_utc`).
- **Never extract date components without timezone context:** `DAYOFWEEK(timestamp_column)` can give inconsistent results across DST boundaries. Always `CONVERT_TZ()` first, then extract.
- **DST complicates date ranges:** A query like `WHERE DATE(ts) BETWEEN '2024-03-10' AND '2024-03-11'` may miss or double-count the spring-forward hour (2–3 AM). Use TIMESTAMPDIFF instead or convert both boundaries to the same timezone before comparison.
- **Test your assumptions in the target zone:** Write a quick query to verify what `CONVERT_TZ()` returns for a known DST transition date in your database. Libraries and databases can disagree on historical DST rules.
- **Related topics:** Handling NULL/UNKNOWN timezones in ETL, idempotent time-based joins, and modeling time dimensions in star schemas. Consider a `dim_date` table that pre-computes DST flags.

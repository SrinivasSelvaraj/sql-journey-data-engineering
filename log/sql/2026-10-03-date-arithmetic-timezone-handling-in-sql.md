---
date: 2026-10-03
phase: sql
topic: Date arithmetic: timezone handling in SQL
---

# Date arithmetic: timezone handling in SQL

*SQL for analytics and engineering*

## Concept

Timezone handling in SQL is critical when working with timestamps across regions, especially in analytics where business events (job postings, user signups, conversions) occur globally but may be stored in UTC. Without explicit timezone conversion, you risk misaligning data—a job posted at "midnight in London" becomes a different local time in New York, and aggregations by date can silently shift events into wrong reporting periods.

Most SQL databases store timestamps in UTC or as timezone-naive values. When you need to report "jobs posted today in each region," you must convert UTC timestamps to local timezones using `AT TIME ZONE` (PostgreSQL), `CONVERT_TZ()` (MySQL), or `TRY_CONVERT()` (SQL Server). The key is understanding: *when* the conversion happens (query time vs. storage), *what* timezone you're converting to, and whether daylight saving time rules apply.

Without timezone awareness, a common failure is comparing raw UTC timestamps to date literals in a user's local timezone, causing off-by-one errors in daily metrics, or aggregating events across midnight boundaries incorrectly. This is especially painful in hiring analytics where "today's job postings" must match what recruiters see in their dashboard.

## Practice

**Problem:** You have `job_postings_fact` with `job_posted_date` stored as UTC DATE. You need to count job postings per day *as seen in each job's location's local timezone*—so a job posted at 23:00 UTC in London counts toward "today" in London time, but a job posted at 01:00 UTC in New York counts as "yesterday" in New York time.

```sql
SELECT
  job_location,
  (job_posted_date AT TIME ZONE 'UTC' AT TIME ZONE 'America/New_York')::DATE AS local_date,
  COUNT(*) AS posting_count
FROM job_postings_fact
WHERE job_location IN ('New York, NY', 'London, UK')
GROUP BY job_location, local_date
ORDER BY job_location, local_date DESC;
```

**Or, for MySQL/SQL Server without native timezone support:**

```sql
SELECT
  job_location,
  DATE(CONVERT_TZ(job_posted_date, '+00:00', 
    CASE WHEN job_location LIKE '%London%' THEN '+01:00' ELSE '-05:00' END)) AS local_date,
  COUNT(*) AS posting_count
FROM job_postings_fact
WHERE job_location IN ('New York, NY', 'London, UK')
GROUP BY job_location, local_date
ORDER BY job_location, local_date DESC;
```

## Notes

- **DST pitfall:** Timezone offsets change seasonally (e.g., ET is UTC-5 in winter, UTC-4 in summer). Use named timezones (`'America/New_York'`) not fixed offsets (`'-05:00'`) whenever possible; the database handles DST rules.
- **Storage vs. query-time conversion:** Store timestamps in UTC always; convert to local timezones only in SELECT clauses or WHERE filters, never during INSERT. This keeps your data portable and auditable.
- **Implicit type coercion:** `job_posted_date AT TIME ZONE 'UTC'` requires the column to be a `TIMESTAMP` type, not `DATE`. If you store as DATE, you've already lost time-of-day information—convert upstream or use `CAST`.
- **Performance consideration:** Timezone conversion on large tables in WHERE clauses can be expensive; pre-compute local date buckets in a dbt model or add a `local_date` column if querying on it repeatedly.
- **Related:** EXTRACT(EPOCH), interval arithmetic (`NOW() - job_posted_date`), and handling NULL timestamps in date aggregations—all interact with timezone logic in unexpected ways.

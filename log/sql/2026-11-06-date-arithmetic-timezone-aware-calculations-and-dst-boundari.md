---
date: 2026-11-06
phase: sql
topic: Date arithmetic: timezone aware calculations and DST boundaries
---

# Date arithmetic: timezone aware calculations and DST boundaries

*SQL for analytics and engineering*

## Concept

Timezone-aware date arithmetic requires explicitly handling both the timezone context of stored timestamps and daylight saving time (DST) transitions. Most databases store timestamps in UTC to avoid ambiguity, but analytical queries often need to group, filter, or calculate intervals in a user's local timezone—where a single wall-clock hour may not exist (spring forward) or occur twice (fall back). Without timezone awareness, you risk silently shifting data by hours, miscounting events during DST boundaries, or producing results that don't match business logic tied to local time.

DST boundaries are particularly treacherous: adding 24 hours to a timestamp is not the same as adding 1 day in a timezone with DST. A query like `timestamp + INTERVAL 1 DAY` works correctly, but naive date arithmetic (`DATE + 1`) loses timezone context entirely. When aggregating events by local date (e.g., "jobs posted per day in US/Eastern"), you must convert UTC timestamps to the target timezone before extracting the date; otherwise, events posted near midnight UTC will fall into the wrong business day.

The fix: always store timestamps in UTC, explicitly cast to target timezone when filtering or grouping by local date, and use interval arithmetic (not date arithmetic) for duration calculations. Most modern SQL engines (PostgreSQL, Snowflake, BigQuery) handle DST correctly if you use `AT TIME ZONE` or `CONVERT_TZ()` and trust their underlying IANA timezone database.

## Practice

**Problem:** You need to count the number of job postings by local date in US/Eastern timezone for the past 7 days. The `job_posted_date` is stored as a UTC timestamp. Handle the case where today's date in US/Eastern may differ from UTC, and ensure DST transitions don't distort the count.

```sql
SELECT
  CAST(
    job_posted_date AT TIME ZONE 'US/Eastern' 
    AS DATE
  ) AS posted_date_eastern,
  COUNT(*) AS posting_count
FROM job_postings_fact
WHERE job_posted_date >= NOW() AT TIME ZONE 'US/Eastern' - INTERVAL '7 days'
  AND job_posted_date < NOW() AT TIME ZONE 'US/Eastern'
GROUP BY CAST(job_posted_date AT TIME ZONE 'US/Eastern' AS DATE)
ORDER BY posted_date_eastern DESC;
```

**Key moves:** 
- Convert `job_posted_date` (UTC) to US/Eastern *before* casting to DATE, so the date boundary aligns with local midnight.
- Use `NOW() AT TIME ZONE 'US/Eastern'` as the reference point to ensure the 7-day window is measured in local time.
- The `AT TIME ZONE` operator handles DST automatically; no manual offset adjustment needed.

## Notes

- **Common mistake:** casting to DATE before timezone conversion (`CAST(job_posted_date AS DATE)`) loses timezone context and produces UTC dates, misaligning with business-local dates by up to 12 hours.
- **DST gotcha:** `INTERVAL '1 DAY'` on a timestamp correctly skips the DST hour; `DATE '2024-03-10' + 1` in US/Eastern may not be 24 hours of wall-clock time.
- **Connects to:** timestamp-at-rest vs. timestamp-at-query strategy; choosing between storing local date columns (denormalization for speed) vs. computed columns; understanding database-specific timezone support (PostgreSQL's `AT TIME ZONE`, Snowflake's `CONVERT_TZ()`, BigQuery's `FORMAT_TIMESTAMP(..., 'America/New_York')`).
- **Interview tip:** mention the UTC-storage principle upfront; it shows you know the canonical pattern and differentiates from developers who store local times and struggle with multi-region queries.
- **Revisit:** window functions grouped by local date; cross-timezone joins; audit tables with created_at fields during DST cutover events.

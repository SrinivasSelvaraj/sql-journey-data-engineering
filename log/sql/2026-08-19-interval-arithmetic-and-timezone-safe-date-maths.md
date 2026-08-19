---
date: 2026-08-19
phase: sql
topic: Interval arithmetic and timezone-safe date maths
---

# Interval arithmetic and timezone-safe date maths

*SQL for analytics and engineering*

## Concept

Interval arithmetic and timezone-safe date math are critical in analytics because most real-world datasets mix multiple timezones, span daylight saving transitions, and require precise duration calculations. A query that works locally may fail silently in production when UTC offsets change or when you aggregate across regions. The core issue: treating dates as simple numbers rather than timezone-aware objects leads to off-by-one errors, fence-post bugs, and silent data corruption that's hard to audit.

Without deliberate timezone handling, you'll miscategorize events by day, shift reporting boundaries, and misalign joins on temporal keys. For interval arithmetic specifically, naïve date subtraction gives you the count of calendar days, not business days or accounting periods—and mixing `DATE` with `TIMESTAMP` types without explicit casting invites implicit conversions that vary by SQL dialect. The fix: always know your system's default timezone, cast explicitly, use interval types for arithmetic, and validate edge cases around DST and year boundaries.

## Practice

**Problem:** Given `job_postings_fact`, find all jobs posted in the last 30 calendar days (from today's date) and calculate how many days each has been open. Return `job_id`, `job_title_short`, `days_open`, and `posted_date_utc`. Assume `job_posted_date` is stored as DATE in the database timezone (US/Eastern), and you need results in UTC.

```sql
SELECT
    job_id,
    job_title_short,
    (CURRENT_DATE - job_posted_date) AS days_open,
    job_posted_date::TIMESTAMP AT TIME ZONE 'US/Eastern' AT TIME ZONE 'UTC' AS posted_date_utc
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
ORDER BY days_open DESC;
```

**Key moves:** Cast the DATE to TIMESTAMP with source timezone, then pivot to UTC. Use `INTERVAL '30 days'` rather than `30` to make intent explicit. Subtract dates only when both are in the same conceptual timezone. Test this around DST boundaries (second Sunday in March, first Sunday in November in US/Eastern).

## Notes

- **Common mistake:** Using `CURRENT_TIMESTAMP` instead of `CURRENT_DATE` and forgetting to truncate to midnight; this shifts your window by hours depending on query execution time.
- **Adjacent topic:** Always pair interval arithmetic with window functions (`LAG`, `LEAD`, `ROW_NUMBER() OVER (ORDER BY date)`) to detect gaps or duplicates in event streams.
- **Edge case to rehearse:** Subtracting dates across a DST transition; the interval changes depending on whether you cross the fold. Test `'2024-03-10'::DATE - '2024-03-09'::DATE` in Eastern time.
- **Performance note:** Pre-cast and filter on the source timezone column, not the derived UTC column, so the filter can use an index on `job_posted_date`.
- **Validation ritual:** Before shipping, run your date logic for (a) a normal day, (b) DST transition day, (c) year boundary, and (d) a leap-year February. Log the results so you can debug in production.

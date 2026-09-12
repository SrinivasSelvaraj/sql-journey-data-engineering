---
date: 2026-09-12
phase: sql
topic: Date arithmetic: timezone handling across DST boundaries
---

# Date arithmetic: timezone handling across DST boundaries

*SQL for analytics and engineering*

## Concept

Timezone handling across daylight saving time (DST) boundaries is critical when performing date arithmetic on timestamps in different regions. When you add or subtract intervals from a timestamp without accounting for DST transitions, you may get unexpected results: a "+1 day" operation that actually moves 23 or 25 hours depending on when DST shifts occur. This becomes especially dangerous when filtering jobs posted "in the last 30 days" across regions or when calculating exact durations for time-sensitive analytics.

The core issue: most SQL databases store timestamps in UTC internally, but applications and users think in local time. When you convert a UTC timestamp to a local timezone, add an interval, and convert back, the DST rule changes can cause off-by-one-hour errors or logical gaps. For example, on a spring-forward date, 2:30 AM doesn't exist; on fall-back dates, 1:30 AM occurs twice. Without explicit timezone handling, your interval arithmetic silently produces incorrect date ranges.

This matters most in production analytics when you're filtering events by posted date across multiple geographic markets, calculating SLAs, or backfilling historical data. Missing this detail can cause jobs posted in one timezone to be excluded from a "last 30 days" report depending on when DST transitions occur, leading to inconsistent row counts and silent data quality issues.

## Practice

**Problem:** You need to find all job postings from the last 30 days in US Eastern time, regardless of when the query runs. The `job_posted_date` is stored as a UTC timestamp. Write a query that correctly handles DST boundaries and doesn't accidentally exclude or double-count jobs.

```sql
SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_posted_date,
    job_location
FROM job_postings_fact
WHERE job_posted_date >= (
    -- Convert current UTC time to US/Eastern, subtract 30 days in that zone,
    -- then convert back to UTC for comparison
    (NOW() AT TIME ZONE 'US/Eastern' - INTERVAL '30 days')
    AT TIME ZONE 'US/Eastern' AT TIME ZONE 'UTC'
)
ORDER BY job_posted_date DESC;
```

**Why this works:** By converting NOW() to 'US/Eastern', subtracting the interval *in that timezone* (so DST rules apply correctly), and converting back to UTC, you ensure the boundary calculation respects DST transitions. The database interprets "30 days ago in Eastern time" correctly even if a DST shift occurred in between.

## Notes

- **Common mistake:** Using `NOW() - INTERVAL '30 days'` directly assumes no DST shift occurs during the 30-day window, which fails roughly twice yearly in DST-observing regions.
- **PostgreSQL vs. others:** PostgreSQL's `AT TIME ZONE` syntax is explicit and reliable; MySQL requires `CONVERT_TZ()` and must have tzinfo tables loaded; Snowflake/BigQuery have different but equally important DST handling functions—always check docs.
- **UTC storage best practice:** Always store timestamps in UTC and convert to local time only for display or business-logic filtering; this decouples schema from DST rule changes (which governments change unpredictably).
- **Adjacent concern:** This overlaps with period/range queries and scheduled job backfills; DST bugs often hide in incremental loads where "last 24 hours" logic drifts over time.
- **Worth revisiting:** Test your date filters around actual DST transition dates (second Sunday in March and first Sunday in November in US); a single manual check can catch silent failures that unit tests miss.

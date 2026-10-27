---
date: 2026-10-27
phase: modelling
topic: Time series dimension for timestamp bucketing
---

# Time series dimension for timestamp bucketing

*Data modelling and warehousing*

## Concept

A time series dimension for timestamp bucketing is a dedicated dimension table that maps granular timestamps to standard time buckets (hour, day, week, month, quarter, year) and their business attributes. Instead of computing `DATE_TRUNC()` or `EXTRACT()` functions repeatedly in queries, you normalize time into a reusable dimension keyed by a standardized date or datetime.

This matters because temporal queries dominate analytics—grouping by week, comparing month-over-month, filtering by fiscal quarter. Without a time dimension, every analyst rebuilds the same bucketing logic, creating inconsistent definitions (does your "week" start Monday or Sunday?), duplicated computation, and queries that obscure intent behind date functions.

It breaks down when business logic depends on consistent temporal definitions. If one team defines Q1 as Jan–Mar and another uses fiscal quarters starting in April, your dashboards contradict each other. Without a single source of truth, you lose the ability to reason about schemas independently—users must always ask "what does this date column actually mean?"

## Practice

**Problem:** You need to answer "How many jobs were posted each calendar week?" and "What's the average salary by month?" You also want to filter for a specific fiscal quarter (Jan–Mar) without writing conditional date logic in every query.

```sql
-- Create a time dimension
CREATE TABLE dim_date AS
SELECT
    CAST(calendar_date AS DATE) AS date_key,
    calendar_date,
    EXTRACT(YEAR FROM calendar_date) AS calendar_year,
    EXTRACT(MONTH FROM calendar_date) AS calendar_month,
    EXTRACT(WEEK FROM calendar_date) AS calendar_week,
    EXTRACT(QUARTER FROM calendar_date) AS calendar_quarter,
    TO_CHAR(calendar_date, 'YYYY-Q') AS fiscal_quarter,
    DAYNAME(calendar_date) AS day_of_week
FROM GENERATE_DATE('2020-01-01', '2025-12-31')
ORDER BY calendar_date;

-- Remodel fact table to use date key
CREATE TABLE job_postings_fact AS
SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    CAST(job_posted_date AS DATE) AS date_key,
    job_location
FROM raw_job_postings;

-- Now queries are clean and consistent
SELECT
    d.calendar_year,
    d.calendar_week,
    COUNT(j.job_id) AS jobs_posted,
    ROUND(AVG(j.salary_year_avg), 2) AS avg_salary
FROM job_postings_fact j
INNER JOIN dim_date d ON j.date_key = d.date_key
WHERE d.fiscal_quarter = '2024-Q1'
GROUP BY d.calendar_year, d.calendar_week
ORDER BY d.calendar_year, d.calendar_week;
```

## Notes

- **Naming consistency:** Use `date_key` (not `date_id`, not `date_fk`) across all fact tables so joins are mechanical; establish naming conventions in your warehouse layer contract.
- **Granularity mismatch:** If your fact table has sub-daily timestamps but your dimension only has dates, you'll lose precision; decide upfront whether you need `datetime_key` or `date_key`.
- **Fiscal vs. calendar:** Business quarters often differ from calendar quarters; bake both into the dimension and let users pick—don't force one definition on everyone.
- **Surrogate vs. natural keys:** Using `DATE` as the key (natural) is simpler than integer surrogates (`20240101`) if your database handles date joins efficiently; benchmark before over-engineering.
- **Related patterns:** Conforms to Kimball's slowly-changing dimensions (SCD Type 0) and the star schema; also consider time-of-day dimensions if sub-daily analysis matters (peak hours, night shifts, etc.).

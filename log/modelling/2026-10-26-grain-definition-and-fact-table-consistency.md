---
date: 2026-10-26
phase: modelling
topic: Grain definition and fact table consistency
---

# Grain definition and fact table consistency

*Data modelling and warehousing*

## Concept

Grain is the atomic level of detail in a fact table—the answer to "what does one row represent?" Without explicit grain definition, the same table can be interpreted different ways, causing aggregation errors and silent bugs. For example, a row might represent one job posting, one application, or one job-posting-per-day; each interpretation changes what's correct to sum.

Fact table consistency means every row obeys the same grain rule. If most rows are job postings but three are job-posting-application pairs, queries that sum salary or count rows will produce garbage. This is especially dangerous because aggregations often run without warning when the grain is ambiguous—you discover the problem weeks later in a dashboard.

When grain is clear and enforced, teammates query confidently. `SUM(salary_year_avg)` either means total salary across postings (grain: one row per job) or needs explicit filtering (grain: one row per job-application). The table itself, not tribal knowledge, tells them which.

## Practice

**Problem:** You inherit `job_postings_fact` and notice it has 47,000 rows. A colleague's query sums `salary_year_avg` to estimate total market compensation. Another analyst filters by `job_posted_date` to track hiring velocity. Both assume different grains—one treats rows as job postings, the other as daily snapshots. The results conflict with reality.

**Root cause:** No grain enforced. Some job IDs appear once; others appear multiple times (reposted or updated). Some rows duplicate when the same job exists in multiple locations.

**Solution:**

```sql
-- Enforce grain: one row per (job_id, job_posted_date, job_location)
-- Deduplicate and document the grain explicitly.

CREATE TABLE job_postings_fact AS
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  ROW_NUMBER() OVER (
    PARTITION BY job_id, job_posted_date, job_location 
    ORDER BY job_id
  ) AS dedup_rank
FROM raw_job_postings
WHERE dedup_rank = 1;

-- Document grain in schema or table comment:
-- GRAIN: One row per unique (job_id, job_posted_date, job_location) combination.
-- salary_year_avg is the average for that posting in that location on that date.
-- Do not SUM salary_year_avg across rows without grouping by job or date first.
```

## Notes

- **Grain mismatch is silent.** Unlike a schema error, wrong grain produces plausible but false numbers. Use data quality tests to validate row count and uniqueness against the declared grain.
- **Conformed dimensions are grain's partner.** If you change grain, all dependent dimensions (date, location, job) must still match each row's meaning.
- **Additive, semi-additive, non-additive facts follow from grain.** Salary is non-additive at the job level but semi-additive by location. Grain clarifies which aggregations are valid.
- **Grain drift happens in incremental loads.** If you append new data without enforcing the same grain rule, old and new rows become incomparable. Version the grain in metadata or add a `grain_version` column.
- **Related: slowly changing dimensions (SCDs), conformed fact tables, and aggregate tables all depend on locked grain.** Grain is the foundation; everything else stacks on it.

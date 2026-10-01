---
date: 2026-10-01
phase: reliability
topic: Cardinality explosion: high-dimension metrics and sampling
---

# Cardinality explosion: high-dimension metrics and sampling

*Quality, reliability and the professional layer*

## Concept

Cardinality explosion occurs when you create metrics by grouping across too many dimensions simultaneously, generating millions of sparse combinations that consume storage, computation, and query time without adding analytical value. Each dimension you add multiplies the result set: if you group by job_title (500 values) × location (1000 values) × date (365 days) × work_from_home (2 values), you're potentially storing 365 million rows for a single metric, most containing zeros or near-zero counts.

This matters in the professional layer because it's the difference between a pipeline that works in dev and one that fails silently in production—cardinality explosion is often invisible until your fact table bloats, your warehouse bill spikes, or aggregations timeout. It forces you to make deliberate choices: which dimensions actually drive business decisions? Which combinations are sparse noise?

Without cardinality discipline, you end up with tables that are technically correct but operationally toxic: expensive to query, slow to refresh, and difficult to debug when downstream consumers depend on them.

## Practice

**Problem:** You're asked to build a daily metric fact table tracking job posting volume and average salary. You naturally want to slice by job_title_short, job_location, job_work_from_home, and job_posted_date. With ~500 titles and ~1000 locations, this creates 1M+ rows per day—and most combinations have zero postings. Your stakeholders only actually care about trends by *region* (10 values) and *remote status*, and they refresh dashboards weekly, not daily.

```sql
-- ❌ Cardinality explosion: 500 titles × 1000 locations × 2 remote × 365 days
CREATE TABLE job_metrics_daily_exploded AS
SELECT
  job_posted_date,
  job_title_short,
  job_location,
  job_work_from_home,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
GROUP BY job_posted_date, job_title_short, job_location, job_work_from_home;

-- ✅ Solution: pre-aggregate to actual business dimensions, roll up to week
WITH job_region AS (
  SELECT
    job_location,
    CASE 
      WHEN job_location LIKE '%NY%' OR job_location LIKE '%NJ%' THEN 'Northeast'
      WHEN job_location LIKE '%CA%' OR job_location LIKE '%WA%' THEN 'West'
      ELSE 'Other'
    END as region
  FROM job_postings_fact
  GROUP BY job_location
)
SELECT
  DATE_TRUNC('week', job_posted_date) as week_start,
  jr.region,
  job_work_from_home,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary,
  COUNT(DISTINCT job_id) as unique_jobs
FROM job_postings_fact j
JOIN job_region jr ON j.job_location = jr.job_location
GROUP BY DATE_TRUNC('week', job_posted_date), jr.region, job_work_from_home;
```

## Notes

- **Sparsity is the silent killer**: A dimension that seems useful (job_title_short) becomes noise when combined with others; validate that 80%+ of your combinations have non-null values before including them.
- **Sampling over precision**: For exploratory fact tables, accept sampling (e.g., 10% of records) early rather than full cardinality; you gain speed and clarity about which dimensions matter before engineering the "final" table.
- **Rollup hierarchies**: Always have predefined aggregation paths (date → week → month; location → region → country) rather than forcing downstream consumers to de-duplicate your cartesian mess.
- **Monitor grain mismatch**: A fact table at job_id grain is different from one at (date, region, title) grain; mixing them in one table guarantees confusion and bugs downstream.
- **Adjacent: slowly changing dimensions**: If job_location or job_title_short changes over time, cardinality can phantom-grow; use SCD Type 2 keys to control the explosion.

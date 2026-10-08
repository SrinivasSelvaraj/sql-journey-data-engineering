---
date: 2026-10-08
phase: modelling
topic: Aggregate fact tables for pre-aggregated performance
---

# Aggregate fact tables for pre-aggregated performance

*Data modelling and warehousing*

## Concept

An aggregate fact table pre-computes and stores common summaries (counts, sums, averages) at a specific grain—for example, salary averages by job title and location, or posting counts by work-from-home status and month. This eliminates the need to scan millions of raw fact rows every time someone asks "what's the average salary for senior engineers in NYC?" Instead of running expensive GROUP BY queries on-demand, the aggregates are materialized once and refreshed on a schedule.

Without aggregate tables, every analytic query forces a full table scan and computation. This becomes painful at scale: a 500M-row fact table grouped seven ways creates scan and memory contention. Aggregate tables also enforce semantic consistency—if five analysts each write their own "average salary by title" query, they might disagree on null handling, outlier exclusion, or date boundaries. Pre-built aggregates enforce a single source of truth.

The trade-off is storage and maintenance: you trade disk space and ETL complexity for query speed and governance. Aggregate tables only pay off when the same summaries are requested repeatedly. Poorly chosen grains (too fine-grained, or too many dimensions) bloat the warehouse without speeding up real queries.

## Practice

**Problem:** Your analytics team asks salary questions 100 times per day: "average salary by job title," "average salary by location," "average salary by title and location," and "posting count by work-from-home status." The raw `job_postings_fact` table has 10M rows and queries are timing out.

```sql
-- Create aggregate fact table at grain: job_title_short, job_location, job_work_from_home
CREATE TABLE job_postings_agg_fact AS
SELECT
    job_title_short,
    job_location,
    job_work_from_home,
    DATE_TRUNC('month', job_posted_date) AS posting_month,
    COUNT(*) AS posting_count,
    COUNT(DISTINCT job_id) AS unique_job_count,
    AVG(salary_year_avg) AS avg_salary,
    MIN(salary_year_avg) AS min_salary,
    MAX(salary_year_avg) AS max_salary,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) AS median_salary
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY 1, 2, 3, 4;

-- Now queries run in milliseconds instead of seconds:
SELECT job_title_short, avg_salary
FROM job_postings_agg_fact
WHERE job_location = 'New York, NY' AND posting_month = '2024-01-01'
ORDER BY avg_salary DESC;
```

## Notes

- **Grain mismatch is silent and dangerous:** If you aggregate at (title, location, month) but someone queries (title, work_from_home), you either miss queries or must add a coarser grain—which balloons table size. Document the grain explicitly in the table name or metadata.
- **Null handling must be deliberate:** Should NULL salaries be excluded before aggregating, or counted as zero? Store your decision in a comment or validation rule; inconsistency breaks trust in the numbers.
- **Connects to slowly changing dimensions:** If job titles evolve (title_id → title_name changes over time), decide whether aggregates use current or historical titles; version your aggregate tables if history matters.
- **Refreshing cadence:** Aggregate tables lag behind raw facts by definition. If you refresh nightly but queries need real-time precision, create a hybrid: aggregate table + small "today" partition of raw facts.
- **Over-aggregation is common:** Resist the urge to pre-build every conceivable summary. Start with the top 3–5 queries your team actually runs; add aggregates as demand signals grow, not as speculation.

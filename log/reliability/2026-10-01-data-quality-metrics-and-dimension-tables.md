---
date: 2026-10-01
phase: reliability
topic: Data quality metrics and dimension tables
---

# Data quality metrics and dimension tables

*Quality, reliability and the professional layer*

## Concept

Data quality metrics transform intuition into accountability. Without them, you deploy pipelines that *appear* to work until they silently degrade. Quality metrics measure completeness (nulls, missing values), accuracy (values outside expected ranges), freshness (staleness of data), and cardinality (unexpected distribution shifts). Dimension tables amplify this: they're the reference tables (locations, job titles, dates) that your fact tables depend on. A broken dimension cascades—if your job_location dimension has duplicates or formatting inconsistencies, every join upstream produces garbage.

The professional layer separates those who "get data in" from those who "own data quality." You own it when you can answer: "When did data start failing, what broke, and did we catch it before it reached users?" This requires pre-flight checks (row counts before/after, null rates, cardinality thresholds) and post-load monitoring. Without metrics, you're flying blind. With them, you have an early warning system.

## Practice

**Problem:** Your job_postings_fact loads daily, but you notice salary_year_avg has nulls that spike inconsistently, and job_location contains both "New York, NY" and "New York" formatted differently. This corrupts downstream reports. You need to establish quality gates that fail the load if metrics breach thresholds.

```sql
-- Create a quality metrics table to log each load
CREATE TABLE job_postings_quality_log (
    load_date DATE,
    total_rows INT,
    null_salary_count INT,
    null_location_count INT,
    null_salary_pct DECIMAL(5,2),
    location_format_issues INT,
    quality_status VARCHAR(20)
);

-- Run quality checks before trusting the load
INSERT INTO job_postings_quality_log
SELECT
    CAST(CURRENT_DATE AS DATE) as load_date,
    COUNT(*) as total_rows,
    COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) as null_salary_count,
    COUNT(CASE WHEN job_location IS NULL THEN 1 END) as null_location_count,
    ROUND(100.0 * COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) / COUNT(*), 2) as null_salary_pct,
    COUNT(CASE WHEN job_location LIKE '%,%' AND job_location NOT LIKE '%, __' THEN 1 END) as location_format_issues,
    CASE 
        WHEN COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) / COUNT(*) > 0.05 THEN 'FAILED'
        WHEN COUNT(CASE WHEN job_location LIKE '%,%' AND job_location NOT LIKE '%, __' THEN 1 END) > 100 THEN 'FAILED'
        ELSE 'PASSED'
    END as quality_status
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE;

-- Alert: only proceed if status = 'PASSED'
SELECT * FROM job_postings_quality_log WHERE load_date = CURRENT_DATE AND quality_status = 'FAILED';
```

## Notes

- **Metric ownership is real work:** Don't set thresholds once and forget them. Review them monthly. Thresholds that made sense in March may be useless by August as data patterns shift.
- **Dimensions need their own SLA:** A dimension table should have guaranteed uniqueness and completeness. Use UNIQUE constraints and NOT NULL. A broken dimension kills trust faster than a fact table hole.
- **Freshness matters more than perfection:** A pipeline that loads 98% clean data daily is more valuable than one that loads 100% clean data weekly. Set freshness SLAs alongside accuracy thresholds.
- **Connect metrics to alerting:** Metrics in a table are decorative until they trigger Slack/PagerDuty alerts. "Someone will look at the log" is not a strategy.
- **Revisit:** Data contracts (formalizing what downstream expects), lineage tracking (where did this bad row come from?), and great expectations framework (Python library for codified quality checks).

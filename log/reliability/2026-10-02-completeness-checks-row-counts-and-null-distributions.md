---
date: 2026-10-02
phase: reliability
topic: Completeness checks: row counts and null distributions
---

# Completeness checks: row counts and null distributions

*Quality, reliability and the professional layer*

## Concept

Completeness checks validate that your data pipeline delivers the expected volume and distribution of non-null values. Row count checks catch dropped records (bad joins, filters that were too aggressive, upstream failures). Null distribution checks catch silent data quality degradation—when a column gradually fills with NULLs because an upstream source changed, a dependency broke, or a transformation logic assumed optional data that became required.

This matters most at the boundary between raw and trusted layers. A pipeline can run without error while systematically losing 20% of rows or populating salary data as NULL for an entire job category. These failures don't trigger exceptions; they degrade trust in decisions built on the data. In a professional data environment, you're expected to catch these before stakeholders notice.

Without completeness checks, you inherit technical debt: analysts build reports on data they assume is complete, models train on biased subsets, and root-cause analysis happens weeks later when revenue metrics don't match predictions.

## Practice

**Problem:** You load job postings daily. Recently, salary data became optional in the source system, but your downstream models assume salary_year_avg is always populated. You need to detect when null rates spike and identify which job categories are most affected.

```sql
-- Row count and null distribution check
WITH source_stats AS (
  SELECT
    COUNT(*) as total_rows,
    COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) as null_salary_count,
    COUNT(CASE WHEN job_location IS NULL THEN 1 END) as null_location_count,
    job_title_short
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
  GROUP BY job_title_short
)
SELECT
  job_title_short,
  total_rows,
  null_salary_count,
  ROUND(100.0 * null_salary_count / total_rows, 2) as salary_null_pct,
  null_location_count,
  ROUND(100.0 * null_location_count / total_rows, 2) as location_null_pct,
  CASE
    WHEN ROUND(100.0 * null_salary_count / total_rows, 2) > 5 THEN 'ALERT: High salary nulls'
    WHEN total_rows < 100 THEN 'ALERT: Low volume'
    ELSE 'OK'
  END as data_quality_flag
FROM source_stats
ORDER BY salary_null_pct DESC;
```

## Notes

- **Row count alone is insufficient.** A pipeline can load the same number of rows yesterday and today while dropping all records from a specific partner or geography—always slice by dimension.
- **Set thresholds based on SLA, not intuition.** "High nulls" means nothing until you define it: 1%? 5%? 10%? Agree on thresholds with stakeholders and version them in code.
- **Completeness checks belong in your test suite, not in dashboards.** Alerts should fail the pipeline or trigger a warning before data reaches consumers; discovery via reporting is a process failure.
- **Connects to freshness and accuracy.** Completeness is one vertex of the data quality triangle—null data might be *complete* but not *fresh* or *accurate*. Revisit together.
- **Common mistake:** Testing only at table level. A table with 1M rows and 50% nulls in one column passes a simple count check; always stratify by column and key dimension (job_title_short, job_location, etc.).

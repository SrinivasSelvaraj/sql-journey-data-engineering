---
date: 2026-11-02
phase: reliability
topic: Completeness: percentage of non-null required columns
---

# Completeness: percentage of non-null required columns

*Quality, reliability and the professional layer*

## Concept

Completeness measures the percentage of non-null values in columns that are required for meaningful analysis or downstream processes. A required column is one that your pipeline, analytics layer, or business logic cannot function without—salary_year_avg in a compensation analysis, or job_location in a geographic filter. Unlike validity (correct format) or accuracy (correct value), completeness is about presence: does the data exist at all?

Without completeness checks, you ship pipelines that silently degrade. A dashboard showing salary trends with 40% nulls looks identical to one with 5% nulls—until someone investigates and finds half your records are useless. More insidiously, nulls propagate: they fail joins, break GROUP BY logic, and corrupt aggregates. The difference between a junior engineer and a trusted owner is catching this *before* it reaches users.

Completeness thresholds are business decisions, not technical ones. You might accept 1% nulls in a large dataset (statistical noise) but 0% nulls in a primary key or 2% in a critical dimension. Define thresholds explicitly, monitor them continuously, and alert when they breach.

## Practice

**Problem:** Your job_postings_fact table is loaded daily. You notice some records have NULL salary_year_avg and NULL job_location. You need to ensure salary and location data are at least 95% complete, and fail the pipeline if they drop below that threshold.

```sql
WITH completeness AS (
  SELECT
    COUNT(*) as total_rows,
    COUNT(salary_year_avg) as salary_non_null,
    COUNT(job_location) as location_non_null,
    ROUND(100.0 * COUNT(salary_year_avg) / COUNT(*), 2) as salary_completeness_pct,
    ROUND(100.0 * COUNT(job_location) / COUNT(*), 2) as location_completeness_pct
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
)
SELECT
  *,
  CASE 
    WHEN salary_completeness_pct < 95 THEN 'FAIL: salary below 95%'
    WHEN location_completeness_pct < 95 THEN 'FAIL: location below 95%'
    ELSE 'PASS'
  END as quality_check
FROM completeness;
```

Run this daily. If the result is 'FAIL', halt downstream processes and investigate the source.

## Notes

- **Threshold creep:** Don't accept "we'll just handle nulls downstream." Define a threshold, enforce it, then negotiate only if business context changes—not data quality.
- **NULL vs. empty string:** A 0-length string is not NULL in SQL. If your source treats missing data as `''` instead of NULL, your completeness check passes falsely. Normalize on ingestion.
- **Intersection with uniqueness & referential integrity:** A complete primary key (100% non-null) is necessary but not sufficient; it must also be unique. Completeness is the first gate.
- **Time-series gotcha:** Completeness can degrade gradually. Track it weekly or monthly, not just at load time. A 98% → 92% → 84% trend is a warning sign.
- **Adjacent: SLA metrics and timeliness.** If a required column is missing 20% of the time because upstream jobs are slow, completeness becomes a timeliness problem—different root cause, same user impact.

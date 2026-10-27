---
date: 2026-10-27
phase: modelling
topic: Ensemble fact tables for multiple grains
---

# Ensemble fact tables for multiple grains

*Data modelling and warehousing*

## Concept

An ensemble fact table holds multiple grain levels in a single table, denormalized to support queries at different aggregation levels without requiring joins to separate fact tables. For example, a job_postings_fact might store both job-level detail (individual posting) and company-level summaries (aggregate hiring volume) in the same structure, distinguished by a grain_level dimension key or by NULL handling in foreign keys.

This matters when business users query at inconsistent granularities—sometimes they want "salaries for this specific posting," other times "average salary by company." Without an ensemble approach, you either force joins across multiple fact tables (slower, error-prone) or duplicate logic across reporting layers, breeding inconsistency.

Without clear grain documentation and design, the same column becomes ambiguous: does salary_year_avg mean the individual job's salary or the company's average? Users run wrong queries, analysts spend time debugging instead of analyzing, and your warehouse becomes a trust liability.

## Practice

**Problem:** Your job_postings_fact has 500K rows at posting-level grain, but the analytics team also needs company-level aggregates (total postings per company, average salary by company, hiring volume trends). They currently write subqueries or pull data into Python, slowing dashboards.

**Solution:** Add a grain_level and company_id dimension key; preserve detail rows and add roll-up rows:

```sql
-- Insert detail-level grain (one row per job posting)
INSERT INTO job_postings_fact
SELECT 
  job_id,
  'POSTING' AS grain_level,
  company_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  1 AS posting_count
FROM raw_job_postings;

-- Insert company-level grain (one row per company per date)
INSERT INTO job_postings_fact
SELECT 
  CONCAT('COMPANY_', company_id, '_', job_posted_date) AS job_id,
  'COMPANY' AS grain_level,
  company_id,
  NULL AS job_title_short,
  AVG(salary_year_avg) AS salary_year_avg,
  NULL AS job_work_from_home,
  job_posted_date,
  NULL AS job_location,
  COUNT(*) AS posting_count
FROM raw_job_postings
GROUP BY company_id, job_posted_date;

-- Query both grains seamlessly
SELECT 
  grain_level,
  company_id,
  AVG(salary_year_avg) AS avg_salary,
  SUM(posting_count) AS total_postings
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
GROUP BY grain_level, company_id;
```

## Notes

- **Grain ambiguity kills trust:** Always add a `grain_level` column and document it in your metadata layer (dbt yml, data dictionary). Never rely on implicit NULL patterns to signal grain.
- **Conformed dimensions are mandatory:** Your company_id must mean the same thing at posting and company grain; misaligned keys introduce silent errors.
- **Consider slowly-changing dimensions:** If company names or locations change, versioning company_id (SCD Type 2) prevents historical queries from showing wrong attributes.
- **This overlaps with semi-additive measures:** salary_year_avg is semi-additive (you can average it, not sum it); document aggregation rules per grain to prevent users from summing what should be averaged.
- **Revisit: normalized vs. denormalized trade-offs**, fact table design patterns (Kimball vs. Data Vault), and grain declaration in dimensional modelling.

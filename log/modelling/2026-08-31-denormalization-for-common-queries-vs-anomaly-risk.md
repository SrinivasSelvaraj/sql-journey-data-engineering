---
date: 2026-08-31
phase: modelling
topic: Denormalization for common queries vs anomaly risk
---

# Denormalization for common queries vs anomaly risk

*Data modelling and warehousing*

## Concept

Denormalization is the intentional duplication of data across tables to optimize query performance and usability, trading storage and update complexity for faster reads and simpler joins. In data warehousing, it's essential because analytical queries often scan millions of rows—normalizing everything forces expensive multi-table joins that slow down dashboards and reports. However, denormalization introduces **update anomalies**: if you store `job_title_short` in both a `job_postings_fact` and a `companies_dim` table, changing a company name in one place but not the other creates inconsistency.

The decision hinges on query patterns. If 90% of your queries need job title, location, and salary together, denormalizing them into a single fact table eliminates joins. If those values change frequently or have complex business rules, that same denormalization becomes a maintenance nightmare. Without careful denormalization, teams resort to asking you what columns mean or building workarounds; with reckless denormalization, data quality collapses.

## Practice

**Problem:** Your analytics team needs to filter and aggregate job postings by title, location, and remote status in every dashboard. Currently, job titles live in a `jobs_dim` table and locations in a `locations_dim` table, forcing three-table joins on every query. This is slow and the team doesn't understand which table to join to.

```sql
-- Before: normalised, slow
SELECT 
  j.job_title_short,
  l.location_name,
  COUNT(*) as posting_count,
  AVG(f.salary_year_avg) as avg_salary
FROM job_postings_fact f
JOIN jobs_dim j ON f.job_id = j.job_id
JOIN locations_dim l ON f.location_id = l.location_id
WHERE f.job_posted_date >= '2024-01-01'
GROUP BY j.job_title_short, l.location_name;

-- After: denormalized, fast, self-documenting
SELECT 
  job_title_short,
  job_location,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01'
GROUP BY job_title_short, job_location;
```

The denormalized schema scans one table, runs in seconds, and is obvious to new users.

## Notes

- **Update anomaly trap:** If `job_title_short` changes (e.g., "Data Eng" → "Data Engineer"), you must update every row in `job_postings_fact`. Use triggers or ETL validation to catch mismatches.
- **Fact table grain matters:** Denormalize attributes that describe the grain of your fact table (one row = one job posting). Don't denormalize company-level data unless every posting has unique company info.
- **Bridges for many-to-many:** If a job posting can have multiple skills, don't flatten them into a single column; use a bridge table (`job_postings_skills`) alongside the denormalized fact.
- **Staging layer pattern:** Keep raw normalized data in staging, then build denormalized facts in your presentation layer. This isolates update logic and keeps ETL testable.
- **Revisit:** Star schema design, slowly changing dimensions (SCD), and materialized views—they all manage the tension between normalization and query performance.

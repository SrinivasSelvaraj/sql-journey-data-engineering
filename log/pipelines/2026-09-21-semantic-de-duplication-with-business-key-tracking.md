---
date: 2026-09-21
phase: pipelines
topic: Semantic de-duplication with business key tracking
---

# Semantic de-duplication with business key tracking

*Pipelines and orchestration*

## Concept

Semantic de-duplication uses business keys—the natural, domain-meaningful identifiers—to detect and handle duplicate records that may differ in surrogate keys or timestamps. Without it, you load the same job posting twice under different `job_id` values, and your fact table grows with phantom records that break aggregations and waste storage.

This matters most in pipelines ingesting from APIs or uncontrolled sources where the same entity arrives via different paths. A job posting scraped on Tuesday and Wednesday is still the same posting; de-duplication ensures you either skip the second load or update the first record cleanly.

Pipelines that ignore semantic de-duplication silently corrupt metrics. Your "total active jobs" becomes 15% inflated. Your revenue dashboards double-count. You notice only when stakeholders complain, and by then duplicate data is already three months deep in your warehouse.

## Practice

**Problem:** Your job posting API returns records with a new `job_id` each day, even for re-posted listings. You must detect duplicates by matching `(job_title_short, job_location, salary_year_avg, job_work_from_home)` and only insert truly new postings.

```sql
-- Stage incoming data and compute business key hash
WITH staging AS (
  SELECT 
    job_title_short,
    job_location,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    MD5(CONCAT(job_title_short, '|', job_location, '|', COALESCE(salary_year_avg, ''), '|', job_work_from_home)) AS business_key
  FROM raw.job_postings_api_load
),
-- Find which business keys already exist in the fact table
existing_keys AS (
  SELECT DISTINCT business_key
  FROM analytics.job_postings_fact
),
-- Only insert records with new business keys
new_records AS (
  SELECT 
    job_title_short,
    job_location,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    business_key
  FROM staging
  WHERE business_key NOT IN (SELECT business_key FROM existing_keys)
)
INSERT INTO analytics.job_postings_fact (job_title_short, job_location, salary_year_avg, job_work_from_home, job_posted_date, business_key)
SELECT job_title_short, job_location, salary_year_avg, job_work_from_home, job_posted_date, business_key
FROM new_records;
```

## Notes

- **Mistake:** Using only the most recent `job_posted_date` as a proxy for uniqueness. Dates repeat; business semantics don't. Always define business keys explicitly with the product owner.
- **Mistake:** Computing business key hashes in application code before load; do it in SQL so the logic is auditable and version-controlled in your DAG.
- **Adjacent topic:** Slowly Changing Dimensions (SCD) Type 2 uses business keys + effective dating to track *changes* rather than just duplicates—a natural next step.
- **Reconnects to:** Idempotent pipeline design. A re-run must not double-insert; the business key check makes that safe even if you replay three days of data.
- **Revisit:** If your business key definition changes (e.g., salary becomes a range, not exact), you need a migration script to re-hash and reconcile existing records. Plan for this early.

---
date: 2026-10-22
phase: reliability
topic: Row-level validation: business logic constraint checking
---

# Row-level validation: business logic constraint checking

*Quality, reliability and the professional layer*

## Concept

Row-level validation enforces business logic constraints that can't be caught by schema alone—ensuring not just that data *exists* and has the right type, but that it makes *sense* in your domain. A salary of $0, a future job posting date, or a work-from-home flag that contradicts the location are all syntactically valid but logically broken. Without these checks, bad data silently propagates downstream, poisoning analytics, breaking SLAs, and eroding trust in your pipelines.

The distinction matters because data shape validation (nulls, types, ranges) is table stakes; business logic validation is what separates ownership from maintenance. It requires domain knowledge—understanding that entry-level roles shouldn't pay $500k, or that certain location-salary combinations are red flags. These constraints live in the transformation layer, not the schema, because they encode decisions about what your org considers valid.

When row-level validation is missing, you catch problems in production dashboards instead of at ingest time. You spend energy debugging whether the data is wrong or the metric is, rather than preventing the wrong data from entering the warehouse.

## Practice

**Problem:** Your data team notices that job_postings_fact contains records with salary_year_avg = 0, job_posted_date in the future (data entry errors), and remote positions tagged with specific cities that don't make sense (data quality lag). You need to validate these before they reach reporting tables.

```sql
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CASE
    WHEN salary_year_avg IS NULL OR salary_year_avg <= 0 THEN 'invalid_salary'
    WHEN job_posted_date > CURRENT_DATE THEN 'future_posted_date'
    WHEN job_work_from_home = TRUE AND job_location NOT IN ('Remote', 'Anywhere') 
         THEN 'conflicting_location_remote'
    WHEN salary_year_avg > 500000 AND job_title_short NOT IN ('C-Level', 'VP', 'Director') 
         THEN 'unusually_high_salary'
    ELSE 'valid'
  END AS validation_status
FROM job_postings_fact
WHERE CASE
  WHEN salary_year_avg IS NULL OR salary_year_avg <= 0 THEN TRUE
  WHEN job_posted_date > CURRENT_DATE THEN TRUE
  WHEN job_work_from_home = TRUE AND job_location NOT IN ('Remote', 'Anywhere') THEN TRUE
  ELSE FALSE
END;
```

Use this query to identify invalid rows, then decide: quarantine them to a staging table, flag them in a validation_log for the source system, or reject the batch. Route valid rows forward.

## Notes

- **Don't solve this in BI tools.** Validation belongs in the transformation layer so invalid data never reaches reports. If you're filtering in Tableau, you've already failed downstream.
- **Parameterize thresholds.** Hard-coded salary caps and title lists become brittle. Store business rules in a config table; join and validate against it. This scales as your org grows.
- **Log rejections separately.** Create a validation_failures table with row-level detail, rejection reason, and timestamp. This is how you talk back to data producers and prove you've blocked problems.
- **Distinguish severity.** Not all constraint violations are equal. A missing email is a blocker; a future date might be a typo. Use severity flags (error vs. warning) and route accordingly.
- **Adjacent: dbt tests, great expectations, and data contracts.** Row-level validation is the SQL/transform layer; dbt tests and GE plug into CI/CD; data contracts formalize the rules. Together they form a quality stack.

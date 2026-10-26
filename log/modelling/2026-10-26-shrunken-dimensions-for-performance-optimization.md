---
date: 2026-10-26
phase: modelling
topic: Shrunken dimensions for performance optimization
---

# Shrunken dimensions for performance optimization

*Data modelling and warehousing*

## Concept

A shrunken dimension is a simplified, denormalized dimension table created by filtering or aggregating a full dimension to match the grain of a fact table. Instead of joining a large dimension every time, you pre-compute the exact attributes needed at the fact table's level of detail, reducing joins and improving query performance.

Shrunken dimensions matter when your full dimension tables are wide (many columns), change frequently, or contain hierarchies you don't always need. Without them, every query pays the cost of joining large tables and filtering to the same subset repeatedly. A 500-column customer dimension becomes a 10-column shrunken dimension when your fact table only tracks order-level geography and tenure bands—queries run faster and code becomes more readable.

The break point comes when dimension joins dominate query time, or when business users repeatedly query the same dimension slice (e.g., "active jobs only" or "jobs in tech roles"). Denormalizing that slice into the fact table or a purpose-built shrunken dimension eliminates redundant work.

## Practice

**Problem:** The `job_postings_fact` table is queried 100 times daily by analysts asking "average salary by job title and work-from-home status for jobs posted in the last 90 days." A full `job_title` dimension exists with 5,000 rows and 30 columns (industry, seniority, skills taxonomy, etc.), but queries only use `job_title_short`. The `job_location` dimension has 50,000 rows. Every query joins both tables and filters on `job_posted_date`, wasting I/O.

**Solution:** Create a shrunken dimension pre-filtered and denormalized for this fact table's grain:

```sql
CREATE TABLE job_postings_shrunken_dim AS
SELECT DISTINCT
  job_title_short,
  job_work_from_home,
  CASE 
    WHEN job_work_from_home THEN 'Remote'
    ELSE 'On-site'
  END AS work_arrangement
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
;

-- Now queries become simpler and faster:
SELECT 
  jsd.job_title_short,
  jsd.work_arrangement,
  AVG(jpf.salary_year_avg) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact jpf
INNER JOIN job_postings_shrunken_dim jsd
  ON jpf.job_title_short = jsd.job_title_short
  AND jpf.job_work_from_home = jsd.job_work_from_home
WHERE jpf.job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY jsd.job_title_short, jsd.work_arrangement
ORDER BY avg_salary DESC;
```

## Notes

- **Maintenance cost vs. query gain:** Shrunken dimensions add an ETL step to rebuild them. Only create one if the same filter/slice is queried repeatedly; otherwise you're optimizing for a pattern that doesn't exist yet.
- **Confuse shrunken with conformed:** A conformed dimension works across multiple fact tables; a shrunken dimension is purpose-built for one fact table's grain. Don't shrink a dimension that should be conformed—you'll fragment your schema.
- **Grain mismatch risk:** If your fact table's grain changes (e.g., you add job-applicant level data), the shrunken dimension becomes stale or irrelevant. Document the grain explicitly in table comments.
- **Adjacent: slowly changing dimensions (SCD) and aggregate tables.** Shrunken dimensions often sit alongside aggregate fact tables (pre-computed rollups). Both trade storage for query speed; design them together.
- **Revisit cardinality:** Before shrinking, profile the full dimension. If it's already small (< 10,000 rows) or narrow (< 15 columns), the gain is negligible—keep the full dimension for flexibility.

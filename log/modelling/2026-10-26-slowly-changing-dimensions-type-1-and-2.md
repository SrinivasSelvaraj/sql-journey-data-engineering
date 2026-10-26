---
date: 2026-10-26
phase: modelling
topic: Slowly changing dimensions type 1 and 2
---

# Slowly changing dimensions type 1 and 2

*Data modelling and warehousing*

## Concept

Slowly Changing Dimensions (SCDs) are strategies for handling attribute changes in dimension tables over time. **Type 1 overwrites history** — when a dimension attribute changes, you update the existing row, losing the old value forever. **Type 2 preserves history** — you insert a new row with a new surrogate key, adding effective date ranges and a "current" flag so you can query both past and present states.

SCD strategy matters because it determines what your fact table can answer. Without it, you either lose analytical history (Type 1) or create unbounded growth and complex joins (Type 2). For example, if a job title changes from "Junior Engineer" to "Senior Engineer," Type 1 means historical salary facts are now joined to "Senior Engineer"; Type 2 means you track both roles with separate keys and know which period each salary belonged to.

Choose Type 1 for attributes that don't matter historically (e.g., a company's current region office location). Choose Type 2 for attributes that alter interpretation of facts (job title, job level, location hierarchy). Misalignment leads to either lost audit trails or performance-killing dimension bloat.

## Practice

**Problem:** Your `job_postings_fact` links to job_location, but companies frequently relocate roles or reclategorize them (remote → hybrid). Queries like "what was the average salary for this job when it was in New York?" break because the location attribute gets overwritten. Design a Type 2 dimension to preserve this history.

```sql
-- job_dim (Type 2)
CREATE TABLE job_dim (
  job_dim_id INT PRIMARY KEY,          -- surrogate key
  job_id INT,                          -- business key
  job_title_short VARCHAR(100),
  job_location VARCHAR(100),
  job_level VARCHAR(50),
  date_effective DATE,
  date_end DATE,
  is_current BOOLEAN,
  dw_load_date TIMESTAMP
);

-- job_postings_fact (modified to use surrogate key)
CREATE TABLE job_postings_fact (
  job_posting_id INT PRIMARY KEY,
  job_dim_id INT REFERENCES job_dim(job_dim_id),
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE
);

-- Query: salary by location at the time the job was posted
SELECT
  jd.job_location,
  AVG(jpf.salary_year_avg) AS avg_salary
FROM job_postings_fact jpf
JOIN job_dim jd 
  ON jpf.job_dim_id = jd.job_dim_id
  AND jpf.job_posted_date BETWEEN jd.date_effective AND jd.date_end
GROUP BY jd.job_location;
```

## Notes

- **Surrogate key trap:** Never use the business key (job_id) as a foreign key in the fact table when using Type 2; you must generate a new surrogate key (job_dim_id) for each dimension version or your joins will be ambiguous.

- **Date ranges vs. single effective date:** Type 2 requires both `date_effective` and `date_end` (or use `is_current` + NULL for open-ended rows). Lazy implementation using only one column breaks time-based joins.

- **Type 2 cardinality explosion:** If a dimension changes frequently (hourly updates), Type 2 creates millions of rows. Consider hybrid approaches: Type 1 for stable attributes, Type 2 only for the ones that change rarely and matter for analysis.

- **Adjacent: conformed dimensions, fact grain, and audit queries.** SCD design must align with your fact table's grain (job posting, not job posting + day) and your team's reporting requirements.

- **Revisit after implementing:** Test both forward-looking (current state) and historical (point-in-time) queries to confirm the design answers the questions your stakeholders actually ask.

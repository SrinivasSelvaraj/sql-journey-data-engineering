---
date: 2026-09-16
phase: modelling
topic: Fact table grain definition and dimension conformance
---

# Fact table grain definition and dimension conformance

*Data modelling and warehousing*

## Concept

Fact table grain defines the atomic level of measurement—the finest detail stored in each row. Before writing a schema, you must answer: *What does one row represent?* Is it one job posting? One application? One salary observation per job per day? Without explicit grain definition, teams query the same table differently, producing contradictory metrics and requiring constant clarification.

Dimension conformance means all descriptive attributes (job_title, location, company) must have a single, consistent definition across the warehouse. If one fact table calls a role "Software Engineer" and another calls it "SWE," joins fail silently and aggregations split incorrectly. Conformed dimensions act as a shared vocabulary—every fact table that references "job_title" points to the same dimension table with identical encodings.

When grain is undefined, you lose reproducibility. A query aggregating salary_year_avg per job_title may double-count if one row represents a posting and another represents a repost. When dimensions aren't conformed, metrics diverge across reports and debugging becomes archaeological work.

## Practice

**Problem:** Your job_postings_fact table conflates two different grains—some rows represent a job posting on a single date, others represent the same posting reposted weeks later. When you sum salary_year_avg grouped by job_title_short, you're summing both original and reposted salaries, inflating totals. You also hardcode job_title_short as text, so "ML Engineer," "Machine Learning Engineer," and "ML Eng" appear as separate categories.

**Solution:**

```sql
-- Define grain explicitly: one row = one posting instance on one date
-- Create conformed job_title dimension
CREATE TABLE dim_job_title (
  job_title_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  job_title_normalized VARCHAR(100),  -- "ML Engineer"
  job_category VARCHAR(50)
);

-- Remodel fact table with foreign key, atomic grain
CREATE TABLE fact_job_postings (
  job_posting_id INT PRIMARY KEY,
  job_title_id INT NOT NULL REFERENCES dim_job_title(job_title_id),
  company_id INT NOT NULL,
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE NOT NULL,
  job_location_id INT NOT NULL,
  CONSTRAINT grain_pk UNIQUE (job_posting_id, job_posted_date)
);

-- Query now has consistent semantics
SELECT dt.job_title_normalized, SUM(f.salary_year_avg) as total_salary
FROM fact_job_postings f
JOIN dim_job_title dt ON f.job_title_id = dt.job_title_id
WHERE f.job_posted_date = '2024-01-15'
GROUP BY dt.job_title_normalized;
```

## Notes

- **Grain ambiguity is silent.** Wrong grain produces plausible numbers that are wrong. Always document: "one row per X per Y" in schema comments.
- **Conform early or pay later.** Changing a dimension value after 6 months of queries breaks historical comparisons; build a single source of truth upfront, even if it's small.
- **Slowly Changing Dimensions (SCD)** solve the problem of dimension attributes changing over time (e.g., a job title gets renamed). Use SCD Type 2 (new row with version date) if historical accuracy matters.
- **Bridge tables** handle many-to-many relationships. If one job posting belongs to multiple job categories, don't denormalize into fact; create `fact_job_posting_categories(job_posting_id, category_id)`.
- **Revisit:** Fact table additivity (can you sum this measure?), dimensional hierarchy (job_title → job_category → industry), and slowly changing dimensions when modeling employee or company attributes.

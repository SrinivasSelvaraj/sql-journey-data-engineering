---
date: 2026-11-10
phase: modelling
topic: Star schema: facts, dimensions and conformed dimensions
---

# Star schema: facts, dimensions and conformed dimensions

*Data modelling and warehousing*

## Concept

A star schema organizes a data warehouse into a central **fact table** (containing measurable events and foreign keys) surrounded by **dimension tables** (containing descriptive attributes). This design lets analysts write simpler queries and self-serve analytics without asking you what `job_posted_date` or `job_work_from_home` actually mean—the semantic layer is explicit in the structure.

**Conformed dimensions** are dimension tables shared across multiple fact tables with identical structure and semantics. For example, a `dim_date` table used by both job postings and application events ensures everyone calculates "jobs posted in Q4" the same way. Without this discipline, two teams calculate the same metric differently, metrics diverge, and trust erodes.

The problem occurs when you embed all attributes into one fact table (the "flat" approach): queries bloat, dimension values repeat millions of times (storage waste), and there's no single source of truth for what "remote work" means. Star schemas compress dimensions, enforce consistency, and make the data model readable like a diagram.

## Practice

**Problem:** Your `job_postings_fact` mixes low-cardinality attributes (job title, location, work-from-home flag) with measurements (salary). When you need to add job category, seniority level, and company size, the fact table becomes cluttered and you lose the ability to quickly answer: "What is the average salary for mid-level remote data engineer roles in NYC?"

**Solution:** Separate into fact and dimension tables with conformed dimensions:

```sql
-- Fact table: one row per job posting event
CREATE TABLE job_postings_fact (
  job_posting_id INT PRIMARY KEY,
  job_title_dim_id INT,
  location_dim_id INT,
  date_dim_id INT,
  salary_year_avg DECIMAL,
  FOREIGN KEY (job_title_dim_id) REFERENCES dim_job_title,
  FOREIGN KEY (location_dim_id) REFERENCES dim_location,
  FOREIGN KEY (date_dim_id) REFERENCES dim_date
);

-- Conformed dimension: reuse across fact tables
CREATE TABLE dim_job_title (
  job_title_dim_id INT PRIMARY KEY,
  job_title_short VARCHAR,
  job_category VARCHAR,
  seniority_level VARCHAR
);

CREATE TABLE dim_location (
  location_dim_id INT PRIMARY KEY,
  location VARCHAR,
  is_remote BOOLEAN,
  country VARCHAR
);

-- Query becomes clear and fast:
SELECT 
  jt.job_title_short,
  jt.seniority_level,
  AVG(fpf.salary_year_avg) AS avg_salary
FROM job_postings_fact jpf
JOIN dim_job_title jt ON jpf.job_title_dim_id = jt.job_title_dim_id
JOIN dim_location loc ON jpf.location_dim_id = loc.location_dim_id
WHERE jt.seniority_level = 'mid-level'
  AND loc.is_remote = TRUE
  AND loc.country = 'USA'
GROUP BY jt.job_title_short, jt.seniority_level;
```

## Notes

- **Surrogate keys matter**: Use auto-incrementing integers (job_title_dim_id) instead of natural keys (job_title_short) in fact tables. Natural keys change; surrogates don't. Insulates your fact table from dimension churn.

- **Slowly Changing Dimensions (SCD)**: Job titles and locations evolve. Decide early: do you track Type 1 (overwrite history), Type 2 (keep versions with effective dates), or Type 3 (keep current and previous)? Mishandling this breaks historical analysis.

- **Conformed dimension discipline**: If two teams build separate location dimensions, one with `is_remote` and one without, metrics won't align. Enforce a single source of truth; divergence is a sign your data governance is slipping.

- **Grain and additivity**: Define fact table grain explicitly (one row per job posting, not per applicant per posting). Only additive measures belong in facts; ratios belong in views. Mixing breaks SUM() aggregations.

- **Adjacent: data vault, normalized OLTP vs. denormalized OLAP**: Star schema is denormalized for query speed. Compare to Data Vault (hub-satellite-link) for audit trails, or fully normalized 3NF for transaction systems. Each serves different purposes.

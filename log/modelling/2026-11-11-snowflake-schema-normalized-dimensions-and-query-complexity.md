---
date: 2026-11-11
phase: modelling
topic: Snowflake schema: normalized dimensions and query complexity
---

# Snowflake schema: normalized dimensions and query complexity

*Data modelling and warehousing*

## Concept

A Snowflake schema extends the star schema by normalizing dimension tables into multiple levels. Instead of a single flat `jobs_dimension` table, you break it into related tables: `job_title_dimension` → `job_category_dimension`, or `location_dimension` → `country_dimension`. This reduces redundancy and makes updates safer—change a job category name once, not 10,000 times across fact rows.

The cost is query complexity: you now need more JOINs to reconstruct a complete business view. Snowflake schemas matter when you have high-cardinality dimensions with many repeated values (job titles, locations, companies) that change over time. Without normalization, your warehouse bloats, and a single typo in a dimension value creates data quality chaos that breaks downstream reports.

Breaking without it: analysts can't trust which records belong together, dimension updates require fact table rewrites, and queries become slow because storage and memory overhead forces more disk I/O per query.

## Practice

**Problem:** Your `job_postings_fact` table has `job_title_short` and `job_location` as strings. Over three months, you notice "Senior Data Engineer" appears as "Senior Data Engineer", "Sr. Data Engineer", and "Senior DE" across 50,000 rows. This makes aggregation by role unreliable. How do you normalize this?

```sql
-- Create normalized dimension tables
CREATE TABLE job_title_dimension (
  job_title_id INT PRIMARY KEY,
  job_title_short VARCHAR,
  job_category VARCHAR,
  seniority_level VARCHAR,
  created_at TIMESTAMP
);

CREATE TABLE location_dimension (
  location_id INT PRIMARY KEY,
  location_name VARCHAR,
  city VARCHAR,
  country VARCHAR,
  remote_eligible BOOLEAN
);

-- Refactor fact table to use foreign keys
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_id INT NOT NULL REFERENCES job_title_dimension(job_title_id),
  location_id INT NOT NULL REFERENCES location_dimension(location_id),
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE
);

-- Query now joins cleanly
SELECT 
  jt.job_category,
  ld.country,
  COUNT(*) as postings,
  AVG(jpf.salary_year_avg) as avg_salary
FROM job_postings_fact jpf
JOIN job_title_dimension jt ON jpf.job_title_id = jt.job_title_id
JOIN location_dimension ld ON jpf.location_id = ld.location_id
GROUP BY jt.job_category, ld.country;
```

## Notes

- **Late-binding joins are expensive:** Snowflake schemas force more JOINs at query time; use query result caching and clustering keys on foreign keys to mitigate slow performance.
- **Dimension creep trap:** Don't over-normalize too early. Start star schema, normalize only when a dimension has >10K distinct values or changes frequently.
- **Slowly changing dimensions (SCD):** Snowflake schemas pair naturally with SCD Type 2 (versioning with effective dates); track which job title version was active when the posting was made.
- **Surrogate vs. natural keys:** Always use surrogate keys (auto-increment IDs) as foreign keys, not business strings like job titles—strings change, IDs don't.
- **Connects to:** dimensional modeling, fact table grain, conformed dimensions, data lineage tracking, and test-driven warehouse design (validate dimension integrity before fact loads).

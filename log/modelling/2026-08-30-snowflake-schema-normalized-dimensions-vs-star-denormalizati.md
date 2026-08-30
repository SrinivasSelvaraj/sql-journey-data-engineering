---
date: 2026-08-30
phase: modelling
topic: Snowflake schema: normalized dimensions vs star denormalization
---

# Snowflake schema: normalized dimensions vs star denormalization

*Data modelling and warehousing*

## Concept

A **star schema** denormalizes dimensions into a single flat table per dimension; a **snowflake schema** normalizes dimensions further into related lookup tables. In a star schema, `job_postings_fact` might have `job_title_short` and `job_category` embedded directly. In snowflake, you'd separate `job_title` into its own `dim_job_title(job_title_id, title_short, title_long, category_id)` table, and `category` into `dim_category(category_id, category_name)`.

The trade-off is real: star schemas are faster to query (fewer joins, wider fact tables) and simpler for analysts unfamiliar with the domain. Snowflake schemas save storage, enforce consistency (one place to update a job category name), and scale better when dimensions have many attributes or hierarchies. Without normalization, you risk duplicate values, update anomalies, and analysts guessing whether `job_title_short` matches the canonical source. Without denormalization, you risk slow queries and analyst frustration chasing joins across five tables.

Choose based on query patterns and team skill. High-volume analytical queries with stable dimensions favor star. Systems with frequent dimension updates, strict governance, or very wide dimensions favor snowflake.

## Practice

**Problem:** Your `job_postings_fact` table stores `job_location` as a string (e.g., "New York, NY"). Multiple job posts repeat "New York, NY", but sometimes it appears as "New York" or "NY, United States". Analysts can't reliably count jobs by location, and there's no single source of truth for location names or regions.

**Solution – normalize into snowflake:**

```sql
-- Create normalized location dimension
CREATE TABLE dim_location (
  location_id INT PRIMARY KEY,
  location_name VARCHAR,
  city VARCHAR,
  state_code VARCHAR,
  country VARCHAR,
  region_id INT,
  FOREIGN KEY (region_id) REFERENCES dim_region(region_id)
);

-- Create region dimension (one level up the hierarchy)
CREATE TABLE dim_region (
  region_id INT PRIMARY KEY,
  region_name VARCHAR
);

-- Refactor fact table
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_id INT,
  salary_year_avg DECIMAL,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  location_id INT,
  FOREIGN KEY (job_title_id) REFERENCES dim_job_title(job_title_id),
  FOREIGN KEY (location_id) REFERENCES dim_location(location_id)
);

-- Now analysts query with confidence
SELECT 
  r.region_name,
  COUNT(jp.job_id) as job_count,
  AVG(jp.salary_year_avg) as avg_salary
FROM job_postings_fact jp
JOIN dim_location l ON jp.location_id = l.location_id
JOIN dim_region r ON l.region_id = r.region_id
GROUP BY r.region_name;
```

## Notes

- **Overcomplication trap:** snowflake doesn't solve data quality—garbage in the dimension tables is still garbage. Normalize only dimensions that have true hierarchies, repeated values, or separate ownership.
- **Query performance cost:** each normalized level adds a join; use materialized views or denormalized aggregation tables if analysts repeatedly query across many levels.
- **Version history and SCD:** if dimensions change (e.g., job category renames), snowflake makes it easier to track slowly changing dimensions (SCD Type 2: add effective_date and is_current columns). Star schemas make this harder without duplication.
- **Adjacent topics:** conformation (shared dimensions across fact tables), fact table granularity (one row per job post vs. per application), and kimball methodology (the design framework behind both patterns).
- **Revisit when:** you notice analysts writing the same join logic repeatedly, or data stewards report inconsistencies; that signals a dimension is ripe for snowflaking.

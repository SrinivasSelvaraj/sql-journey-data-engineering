---
date: 2026-10-09
phase: modelling
topic: Outrigger dimensions for hierarchies
---

# Outrigger dimensions for hierarchies

*Data modelling and warehousing*

## Concept

An outrigger dimension is a separate dimension table that extends a hierarchy beyond what fits naturally in a single dimension table. Instead of flattening all levels of a hierarchy into one wide table, you create a dedicated dimension for the lower levels and link it via a foreign key. This keeps hierarchies normalized, reduces redundancy, and makes the warehouse easier to maintain.

Outriggers matter when you have multi-level hierarchies (location → region → country, or job_category → job_subcategory → job_family) where intermediate levels have their own attributes that don't belong in the fact table. Without outriggers, you either denormalize aggressively (creating sparse columns and update nightmares) or force every hierarchy into a single slowly-changing dimension, making it hard to track changes at different grain levels independently.

Without proper outrigger design, you'll face: duplicate data (same region name repeated across thousands of rows), slow updates (changing one region's metadata forces updates across millions of fact records), and confused queries (analysts won't know which column represents "the official location hierarchy" vs. denormalized copies).

## Practice

**Problem:** Your job_postings_fact table has a job_location column with raw values like "San Francisco, CA" and "New York, NY". You need to support hierarchical queries (jobs by city, state, and country) with attributes like state_tax_rate and country_timezone that shouldn't be repeated in every fact row.

```sql
-- Create outrigger dimension for geographic hierarchy
CREATE TABLE dim_location (
  location_id INT PRIMARY KEY,
  city_name VARCHAR(100),
  state_id INT,  -- FK to dim_state
  country_id INT, -- FK to dim_country
  latitude DECIMAL(9,6),
  longitude DECIMAL(9,6)
);

CREATE TABLE dim_state (
  state_id INT PRIMARY KEY,
  state_code VARCHAR(2),
  state_name VARCHAR(50),
  country_id INT,
  state_tax_rate DECIMAL(5,3)
);

CREATE TABLE dim_country (
  country_id INT PRIMARY KEY,
  country_code VARCHAR(2),
  country_name VARCHAR(50),
  timezone_offset INT
);

-- Refactored fact table
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  location_id INT,  -- FK to dim_location instead of raw text
  FOREIGN KEY (location_id) REFERENCES dim_location(location_id)
);

-- Query that now works cleanly
SELECT 
  j.job_title_short,
  AVG(j.salary_year_avg) AS avg_salary,
  l.city_name,
  s.state_name,
  s.state_tax_rate,
  c.country_name
FROM job_postings_fact j
JOIN dim_location l ON j.location_id = l.location_id
JOIN dim_state s ON l.state_id = s.state_id
JOIN dim_country c ON s.country_id = c.country_id
WHERE c.country_code = 'US'
GROUP BY l.city_name, s.state_name, c.country_name;
```

## Notes

- **Outrigger ≠ snowflaking:** Outriggers are targeted—use them only for true hierarchies with independent attributes; over-normalizing every dimension kills query performance and clarity.
- **Slowly-changing dimensions get complicated:** When a state's tax_rate changes, use SCD Type 2 on dim_state; the location_id in the fact table points to a specific version, so historical accuracy is preserved automatically.
- **Don't confuse with bridge tables:** Bridge tables solve many-to-many problems (an employee in multiple departments); outriggers solve one-to-many hierarchies. Different tools for different shapes.
- **Foreign key constraints in warehouses:** Some teams skip FK constraints for performance; consider whether your query engine validates them anyway—if it does, declare them; if not, document the relationship clearly.
- **Adjacent skills:** Review conformed dimensions (shared state dimension across multiple facts), slowly-changing dimensions (how hierarchies evolve), and the trade-off between star schema (simple, denormalized) vs. snowflake schema (normalized, complex).
